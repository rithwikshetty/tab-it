import Foundation

public struct CurrencyMetadata: Hashable, Identifiable, Sendable {
    public let code: String
    public let symbol: String
    public let name: String
    public let fractionDigits: Int

    public var id: String { code }

    public init(code: String, symbol: String, name: String, fractionDigits: Int) {
        self.code = code
        self.symbol = symbol
        self.name = name
        self.fractionDigits = fractionDigits
    }
}

public enum CurrencyCatalog {
    public static let defaultCode = "INR"
    public static let maximumSupportedFractionDigits = 8

    public static let supportedCodes: [String] = Locale.commonISOCurrencyCodes.sorted()

    public static let supported: [CurrencyMetadata] = supportedCodes
        .map { metadata(forNormalizedCode: $0) }

    private static let supportedCodeSet = Set(supportedCodes)
    private static let metadataByCode = Dictionary(uniqueKeysWithValues: supported.map { ($0.code, $0) })
    private static let localizedSymbolsByCode = makeLocalizedSymbolsByCode()

    public static func normalizedCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func isSupported(_ code: String) -> Bool {
        supportedCodeSet.contains(normalizedCode(code))
    }

    public static func metadata(for code: String) -> CurrencyMetadata? {
        metadataByCode[normalizedCode(code)]
    }

    public static func displayMetadata(for code: String) -> CurrencyMetadata {
        let normalized = normalizedCode(code)
        if let metadata = metadataByCode[normalized] {
            return metadata
        }
        return metadata(forNormalizedCode: normalized)
    }

    public static func fractionDigits(for code: String) -> Int {
        displayMetadata(for: code).fractionDigits
    }

    public static func minorUnitMultiplier(for code: String) -> Decimal {
        powerOfTen(fractionDigits(for: code))
    }

    public static func hasValidPrecision(_ amount: Decimal, currency: String) -> Bool {
        let multiplier = minorUnitMultiplier(for: currency)
        let scaled = amount * multiplier
        return scaled == roundedToInteger(scaled)
    }

    /// Rounds an amount to the currency's minor-unit scale. Midpoint ties are
    /// rounded away from zero so normalization is deterministic across clients.
    public static func normalizedAmount(_ amount: Decimal, currency: String) -> Decimal {
        var input = amount
        var result = Decimal()
        NSDecimalRound(&result, &input, fractionDigits(for: currency), .plain)
        return result
    }

    /// Names pre-folded once — folding every currency name on each keystroke is
    /// what made search-as-you-type drag.
    private static let foldedNames: [String] = supported.map {
        $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    public static func search(_ query: String) -> [CurrencyMetadata] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return supported }

        let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return supported.enumerated().filter { index, currency in
            currency.code.localizedCaseInsensitiveContains(trimmed)
                || currency.symbol.localizedCaseInsensitiveContains(trimmed)
                || foldedNames[index].contains(folded)
        }.map(\.element)
    }

    private static func metadata(forNormalizedCode code: String) -> CurrencyMetadata {
        CurrencyMetadata(
            code: code,
            symbol: symbol(for: code),
            name: Locale.current.localizedString(forCurrencyCode: code) ?? code,
            fractionDigits: fractionDigits(forNormalizedCode: code)
        )
    }

    private static func fractionDigits(forNormalizedCode code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return min(max(formatter.maximumFractionDigits, 0), maximumSupportedFractionDigits)
    }

    private static func symbol(for code: String) -> String {
        if let symbol = localizedSymbolsByCode[code] {
            return symbol
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol.map(cleanSymbol) ?? code
    }

    /// Claim order for symbols shared across currencies ("$", "£", "¥", "kr"):
    /// the most-traded currency keeps the bare symbol and every later claimant
    /// takes a still-free disambiguated candidate ("CA$", "A$") or its code.
    /// Amounts render symbol-only, so two supported currencies must never
    /// display the same symbol.
    private static let symbolClaimPriority: [String] = [
        "USD", "EUR", "JPY", "GBP", "CNY", "AUD", "CAD", "CHF", "HKD", "SGD",
        "SEK", "KRW", "NOK", "NZD", "INR", "MXN", "TWD", "ZAR", "BRL", "DKK",
    ]

    private static func makeLocalizedSymbolsByCode() -> [String: String] {
        var candidatesByCode: [String: Set<String>] = [:]

        for identifier in Locale.availableIdentifiers {
            let locale = Locale(identifier: identifier)
            guard let code = locale.currency?.identifier,
                  supportedCodeSet.contains(code) else { continue }

            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .currency
            formatter.currencyCode = code
            guard let symbol = formatter.currencySymbol.map(cleanSymbol), !symbol.isEmpty else { continue }
            candidatesByCode[code, default: []].insert(symbol)
        }

        // A reference locale contributes the disambiguated variants ("A$",
        // "MX$", "CN¥") that home locales never use, and guarantees every
        // supported code enters the claim pass.
        for code in supportedCodes {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .currency
            formatter.currencyCode = code
            if let symbol = formatter.currencySymbol.map(cleanSymbol), !symbol.isEmpty {
                candidatesByCode[code, default: []].insert(symbol)
            }
        }

        let rank = Dictionary(uniqueKeysWithValues: symbolClaimPriority.enumerated().map { ($1, $0) })
        let orderedCodes = candidatesByCode.keys.sorted { lhs, rhs in
            let lhsRank = rank[lhs] ?? Int.max
            let rhsRank = rank[rhs] ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs < rhs
        }

        // NFKC-fold claim keys so lookalike variants collide: fullwidth "￥"
        // must not pass as distinct from JPY's "¥".
        func claimKey(_ symbol: String) -> String {
            symbol.precomposedStringWithCompatibilityMapping.uppercased()
        }

        var claimed: Set<String> = []
        var result: [String: String] = [:]
        for code in orderedCodes {
            let candidates = candidatesByCode[code]!.sorted { lhs, rhs in
                let lhsIsCode = lhs.uppercased() == code
                let rhsIsCode = rhs.uppercased() == code
                if lhsIsCode != rhsIsCode { return !lhsIsCode }
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lhs < rhs
            }
            let symbol = candidates.first { !claimed.contains(claimKey($0)) } ?? code
            claimed.insert(claimKey(symbol))
            result[code] = symbol
        }
        return result
    }

    private static func cleanSymbol(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{200E}", with: "")
            .replacingOccurrences(of: "\u{200F}", with: "")
            .replacingOccurrences(of: "\u{061C}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func powerOfTen(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        return (0..<exponent).reduce(Decimal(1)) { result, _ in result * 10 }
    }

    private static func roundedToInteger(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }
}
