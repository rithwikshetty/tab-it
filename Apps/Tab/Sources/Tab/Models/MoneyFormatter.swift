import Foundation
import TabCore

enum MoneyFormatter {
    // NumberFormatter is expensive to create and these functions run per row in
    // every list render, so formatters are built once per fraction-digit count
    // and reused (NumberFormatter is thread-safe for formatting).
    private static let plainFormatters: [NumberFormatter] = makeFormatters(grouping: false, posix: true)
    private static let groupedFormatters: [NumberFormatter] = makeFormatters(grouping: true, posix: false)

    private static func makeFormatters(grouping: Bool, posix: Bool) -> [NumberFormatter] {
        (0...CurrencyCatalog.maximumSupportedFractionDigits).map { digits in
            let formatter = NumberFormatter()
            if posix { formatter.locale = Locale(identifier: "en_US_POSIX") }
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = digits
            formatter.maximumFractionDigits = digits
            formatter.usesGroupingSeparator = grouping
            return formatter
        }
    }

    private static func formatter(in cache: [NumberFormatter], fractionDigits: Int) -> NumberFormatter {
        cache[min(max(fractionDigits, 0), CurrencyCatalog.maximumSupportedFractionDigits)]
    }

    static func currencySymbol(_ code: String) -> String {
        CurrencyCatalog.displayMetadata(for: code).symbol
    }

    static func amountPlaceholder(currency: String) -> String {
        plainAmountString(0, currency: currency)
    }

    static func sanitizeAmountInput(_ input: String, currency: String) -> String {
        let fractionDigits = CurrencyCatalog.fractionDigits(for: currency)
        let kept = input.filter { $0.isNumber || $0 == "." || $0 == "," }
        let dots = kept.filter { $0 == "." }.count
        let commas = kept.filter { $0 == "," }.count

        // Pasted formatted numbers carry grouping separators; strip them before
        // the keystroke pass so "1,234.56" stays 1234.56 instead of becoming 1.23.
        let normalized: String
        if dots > 0, commas > 0 {
            // Mixed separators: the one appearing last is the decimal point.
            let decimalIsDot = kept.lastIndex(of: ".")! > kept.lastIndex(of: ",")!
            let grouping: Character = decimalIsDot ? "," : "."
            normalized = kept
                .filter { $0 != grouping }
                .replacingOccurrences(of: ",", with: ".")
        } else if dots > 1 {
            normalized = kept.filter { $0 != "." }
        } else if commas > 1 {
            normalized = kept.filter { $0 != "," }
        } else {
            normalized = kept.replacingOccurrences(of: ",", with: ".")
        }

        var output = ""
        var hasDecimalSeparator = false
        var fractionCount = 0
        for character in normalized {
            if character.isNumber {
                if hasDecimalSeparator {
                    // Truncate beyond the currency's precision — appending would
                    // silently scale the amount.
                    guard fractionCount < fractionDigits else { break }
                    fractionCount += 1
                }
                output.append(character)
            } else if character == "." {
                // A decimal point a zero-decimal currency can't represent ends
                // the number; anything after it is dropped, not concatenated.
                guard fractionDigits > 0, !hasDecimalSeparator else { break }
                hasDecimalSeparator = true
                output.append(character)
            }
        }
        return output
    }

    /// Re-renders a committed amount string for a different currency,
    /// preserving the numeric value (rounded to the new precision) instead of
    /// re-sanitizing digits — switching USD "123.45" to JPY must give 123,
    /// not 12345.
    static func convertAmountText(_ input: String, to currency: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = decimal(from: trimmed) else { return "" }
        return plainAmountString(value, currency: currency)
    }

    static func decimal(from input: String) -> Decimal? {
        Decimal(string: input.replacingOccurrences(of: ",", with: "."))
    }

    /// Sanitizes a share-weight keystroke. Shares are not money: they always
    /// allow up to 2 fraction digits (0.5 for a half pint) regardless of the
    /// expense currency.
    static func sanitizeShareInput(_ input: String) -> String {
        var output = ""
        var hasDecimalSeparator = false
        var fractionCount = 0
        for character in input {
            if character.isNumber {
                if hasDecimalSeparator {
                    guard fractionCount < 2 else { break }
                    fractionCount += 1
                }
                output.append(character)
            } else if character == "." || character == "," {
                guard !hasDecimalSeparator else { break }
                hasDecimalSeparator = true
                output.append(".")
            }
        }
        return output
    }

    /// Renders a share weight without trailing zeros ("2", "0.5", "1.25").
    static func shareString(_ share: Decimal) -> String {
        var value = share
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    static func plainAmountString(_ amount: Decimal, currency: String) -> String {
        let formatter = formatter(in: plainFormatters, fractionDigits: CurrencyCatalog.fractionDigits(for: currency))
        return formatter.string(from: amount as NSDecimalNumber) ?? NSDecimalNumber(decimal: amount).stringValue
    }

    static func format(_ amount: Decimal, currency: String) -> String {
        let metadata = CurrencyCatalog.displayMetadata(for: currency)
        let formatter = formatter(in: groupedFormatters, fractionDigits: metadata.fractionDigits)
        let value = formatter.string(from: amount as NSDecimalNumber) ?? plainAmountString(amount, currency: currency)

        guard metadata.symbol.uppercased() != metadata.code else {
            return "\(metadata.code) \(value)"
        }
        return "\(metadata.code) \(metadata.symbol)\(value)"
    }

    static func format(_ money: Money) -> String {
        format(money.amount, currency: money.currency)
    }

    /// Like `format`, but without the ISO code prefix — just the symbol and amount
    /// (e.g. `£640.00`). Used where the currency is already established by context
    /// (the Overview tab is scoped to one currency). Falls back to the code when the
    /// currency has no distinct symbol, so disambiguation is never fully lost.
    static func formatSymbol(_ amount: Decimal, currency: String) -> String {
        let metadata = CurrencyCatalog.displayMetadata(for: currency)
        let formatter = formatter(in: groupedFormatters, fractionDigits: metadata.fractionDigits)
        let value = formatter.string(from: amount as NSDecimalNumber) ?? plainAmountString(amount, currency: currency)

        guard metadata.symbol.uppercased() != metadata.code else {
            return "\(metadata.code) \(value)"
        }
        return "\(metadata.symbol)\(value)"
    }

    static func formatSigned(_ amount: Decimal, currency: String) -> String {
        let abs = amount < 0 ? -amount : amount
        let prefix: String = amount < 0 ? "-" : ""
        return prefix + format(abs, currency: currency)
    }
}
