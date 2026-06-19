import Foundation

/// Parses a Splitwise group CSV export into trip-shaped rows.
///
/// Splitwise exports one signed **net** column per person (`paid - owed`) rather
/// than the raw payer/split structure. Because `BalanceEngine` derives all
/// balances from per-person nets, any reconstruction that preserves each
/// person's net is balance-exact — even where the original split shape can't be
/// recovered. This parser reconstructs payments + splits that (a) sum exactly to
/// the row's `Cost` (the DB and `SplitCalculator` require this) and (b) preserve
/// each person's net, using deterministic minor-unit remainder distribution.
///
/// The parser is name-based and UUID-free: rows reference people by the display
/// name in the header. The app layer maps names onto trip-person UUIDs. All
/// money math is done in integer minor units (never `Double`).
public enum SplitwiseImport {

    // MARK: - Output shapes

    /// One person's amount within a row. `amount` is always positive.
    public struct Share: Equatable, Sendable {
        public let person: String
        public let amount: Decimal

        public init(person: String, amount: Decimal) {
            self.person = person
            self.amount = amount
        }
    }

    /// A real expense. `payments` (who paid) and `splits` (who owes) each sum to
    /// `total`. People with a zero net are omitted from both.
    public struct ExpenseRow: Equatable, Sendable {
        public let date: Date
        public let description: String
        public let category: String
        public let currency: String
        public let total: Decimal
        public let payments: [Share]
        public let splits: [Share]

        public init(
            date: Date,
            description: String,
            category: String,
            currency: String,
            total: Decimal,
            payments: [Share],
            splits: [Share]
        ) {
            self.date = date
            self.description = description
            self.category = category
            self.currency = currency
            self.total = total
            self.payments = payments
            self.splits = splits
        }
    }

    /// A money transfer between two people. `from` paid `to` (matching tab's
    /// `Settlement.fromUserID -> toUserID` convention).
    public struct SettlementRow: Equatable, Sendable {
        public let date: Date
        public let description: String
        public let currency: String
        public let amount: Decimal
        public let from: String
        public let to: String

        public init(
            date: Date,
            description: String,
            currency: String,
            amount: Decimal,
            from: String,
            to: String
        ) {
            self.date = date
            self.description = description
            self.currency = currency
            self.amount = amount
            self.from = from
            self.to = to
        }
    }

    public enum Row: Equatable, Sendable {
        case expense(ExpenseRow)
        case settlement(SettlementRow)
    }

    /// A non-fatal issue with a single source line. The row may have been skipped
    /// or imported with an adjustment; `message` says which.
    public struct Warning: Equatable, Sendable {
        public let line: Int
        public let message: String

        public init(line: Int, message: String) {
            self.line = line
            self.message = message
        }
    }

    public struct Result: Equatable, Sendable {
        public let people: [String]
        public let rows: [Row]
        public let warnings: [Warning]

        public init(people: [String], rows: [Row], warnings: [Warning]) {
            self.people = people
            self.rows = rows
            self.warnings = warnings
        }

        public var expenses: [ExpenseRow] {
            rows.compactMap { if case let .expense(e) = $0 { return e } else { return nil } }
        }

        public var settlements: [SettlementRow] {
            rows.compactMap { if case let .settlement(s) = $0 { return s } else { return nil } }
        }
    }

    public enum ParseError: Error, Equatable, Sendable {
        case empty
        case missingHeader
        /// The five leading columns weren't the expected Splitwise header.
        case unexpectedHeader(found: [String])
        case noPeople
    }

    static let expectedLeadingColumns = ["Date", "Description", "Category", "Cost", "Currency"]
    static let settlementCategory = "Payment"
    static let settleAllDescription = "Settle all balances"
    static let totalBalanceDescription = "Total balance"

    // MARK: - Entry point

    public static func parse(_ text: String) throws -> Result {
        // Strip a leading UTF-8 BOM so the parser is self-contained regardless of
        // how the file was read.
        let input = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text

        let records = splitRecords(input)
        guard let header = records.first else { throw ParseError.empty }

        let leading = header.fields.prefix(expectedLeadingColumns.count).map(trimmed)
        guard leading.count == expectedLeadingColumns.count else { throw ParseError.missingHeader }
        for (found, expected) in zip(leading, expectedLeadingColumns)
        where found.caseInsensitiveCompare(expected) != .orderedSame {
            throw ParseError.unexpectedHeader(found: leading)
        }

        // Raw header columns keep their positions (for reading cells); `people`
        // is the de-duplicated, first-appearance-ordered list that callers use.
        let columnNames = header.fields.dropFirst(expectedLeadingColumns.count)
            .map(trimmed)
            .filter { !$0.isEmpty }
        var people: [String] = []
        var seen = Set<String>()
        for name in columnNames where seen.insert(name).inserted { people.append(name) }
        guard !people.isEmpty else { throw ParseError.noPeople }

        var rows: [Row] = []
        var warnings: [Warning] = []

        if people.count != columnNames.count {
            warnings.append(Warning(
                line: header.line,
                message: "Duplicate person names in the header are merged into one person."
            ))
        }

        for record in records.dropFirst() {
            parseRow(record, columnNames: columnNames, people: people, into: &rows, warnings: &warnings)
        }

        return Result(people: people, rows: rows, warnings: warnings)
    }

    // MARK: - Row parsing

    private static func parseRow(
        _ record: (line: Int, fields: [String]),
        columnNames: [String],
        people: [String],
        into rows: inout [Row],
        warnings: inout [Warning]
    ) {
        let fields = record.fields
        // Blank separator line.
        if fields.allSatisfy({ trimmed($0).isEmpty }) { return }

        let dateString = field(fields, 0)
        let description = field(fields, 1)
        let category = field(fields, 2)
        let costString = field(fields, 3)
        let currency = CurrencyCatalog.normalizedCode(field(fields, 4))

        // The export's trailing summary row.
        if description.caseInsensitiveCompare(totalBalanceDescription) == .orderedSame { return }

        guard let date = parseDate(dateString) else {
            warnings.append(Warning(line: record.line, message: "Unreadable date \"\(dateString)\"; row skipped."))
            return
        }
        guard let total = parseDecimal(costString), total > 0 else {
            warnings.append(Warning(line: record.line, message: "Unreadable or zero amount; row skipped."))
            return
        }

        // Per-person nets, summing any duplicate-named columns together. A
        // non-empty cell that won't parse skips the whole row rather than
        // silently treating it as zero.
        var netByName: [String: Decimal] = [:]
        for (index, name) in columnNames.enumerated() {
            let raw = field(fields, expectedLeadingColumns.count + index)
            if raw.isEmpty { continue }
            guard let value = parseDecimal(raw) else {
                warnings.append(Warning(line: record.line, message: "Unreadable amount \"\(raw)\"; row skipped."))
                return
            }
            netByName[name, default: 0] += value
        }
        let nets: [(person: String, net: Decimal)] = people.compactMap { name in
            let net = netByName[name] ?? 0
            return net != 0 ? (name, net) : nil
        }

        let isSettlement =
            category.caseInsensitiveCompare(settlementCategory) == .orderedSame
            || description.caseInsensitiveCompare(settleAllDescription) == .orderedSame

        if isSettlement {
            let positives = nets.filter { $0.net > 0 }
            let negatives = nets.filter { $0.net < 0 }
            if positives.count == 1, negatives.count == 1 {
                rows.append(.settlement(SettlementRow(
                    date: date,
                    description: description,
                    currency: currency,
                    amount: total,
                    from: positives[0].person,
                    to: negatives[0].person
                )))
                return
            }
            // A "payment"-shaped row that isn't a clean two-party transfer: fall
            // through to expense reconstruction (balance-identical) with a note.
            warnings.append(Warning(
                line: record.line,
                message: "Payment row \"\(description)\" wasn't a two-person transfer; imported as an expense."
            ))
        }

        guard let reconstructed = reconstruct(
            total: total,
            currency: currency,
            nets: nets,
            people: people,
            line: record.line,
            warnings: &warnings
        ) else { return }

        rows.append(.expense(ExpenseRow(
            date: date,
            description: description,
            category: category,
            currency: currency,
            total: total,
            payments: reconstructed.payments,
            splits: reconstructed.splits
        )))
    }

    // MARK: - Net -> payments/splits reconstruction

    /// Rebuilds payments + splits from per-person nets, anchored on `total`.
    ///
    /// Debtors (net < 0) owe `-net` and paid nothing. Payers (net > 0) share the
    /// remaining `total - debtorOwed` as their owed amount; each payer's paid is
    /// `net + owed`. All arithmetic is in the currency's integer minor units so
    /// sums are exact; the remainder goes to the largest fractional share first
    /// (lowest name on ties), mirroring `BalanceEngine.distributePairs`. Returns
    /// nil (row skipped) for data that can't be reconstructed into a valid,
    /// total-summing expense.
    static func reconstruct(
        total: Decimal,
        currency: String,
        nets: [(person: String, net: Decimal)],
        people: [String],
        line: Int,
        warnings: inout [Warning]
    ) -> (payments: [Share], splits: [Share])? {
        let multiplier = CurrencyCatalog.minorUnitMultiplier(for: currency)
        let costMinor = minorUnits(total, multiplier)

        let netMinor = nets
            .map { (person: $0.person, net: minorUnits($0.net, multiplier)) }
            .filter { $0.net != 0 }

        let debtors = netMinor.filter { $0.net < 0 }
        let payers = netMinor.filter { $0.net > 0 }

        var owedMinor: [(person: String, amount: Int)] = []
        var paidMinor: [(person: String, amount: Int)] = []

        guard !payers.isEmpty else {
            if debtors.isEmpty {
                // Every net is zero: a self-contained expense. Attribute it to the
                // first listed person so it stays a valid, balance-neutral row.
                guard let solo = people.first else { return nil }
                warnings.append(Warning(
                    line: line,
                    message: "Row has no balances; recorded as paid in full by \(solo)."
                ))
                return ([Share(person: solo, amount: total)], [Share(person: solo, amount: total)])
            }
            warnings.append(Warning(line: line, message: "Row doesn't balance (no payer); skipped."))
            return nil
        }

        let debtorOwedTotal = debtors.reduce(0) { $0 - $1.net }   // sum of -net
        let payersOwedTotal = costMinor - debtorOwedTotal
        guard payersOwedTotal >= 0 else {
            warnings.append(Warning(line: line, message: "Row doesn't balance (debts exceed the amount); skipped."))
            return nil
        }

        for debtor in debtors {
            owedMinor.append((debtor.person, -debtor.net))
        }

        // Distribute the payers' shared owed amount proportionally to surplus.
        // The proportion is computed in Decimal (38-digit precision) to avoid
        // Int64 overflow on large expenses, then floored to integer minor units;
        // the remainder goes to the largest fractional share first (lowest name
        // on ties), mirroring BalanceEngine.distributePairs.
        let totalSurplus = payers.reduce(0) { $0 + $1.net }
        let owedTotalDecimal = Decimal(payersOwedTotal)
        let surplusDecimal = Decimal(totalSurplus)
        let sortedPayers = payers.sorted { $0.person < $1.person }
        var shares = [Int](repeating: 0, count: sortedPayers.count)
        var fractions: [(index: Int, fraction: Decimal)] = []
        var allocated = 0
        for (index, payer) in sortedPayers.enumerated() {
            let raw = owedTotalDecimal * Decimal(payer.net) / surplusDecimal
            let floored = floorToInt(raw)
            shares[index] = floored
            allocated += floored
            fractions.append((index, raw - Decimal(floored)))
        }
        var leftover = payersOwedTotal - allocated
        let order = fractions.sorted {
            $0.fraction != $1.fraction ? $0.fraction > $1.fraction
                : sortedPayers[$0.index].person < sortedPayers[$1.index].person
        }
        var next = 0
        while leftover > 0 {
            shares[order[next % order.count].index] += 1
            leftover -= 1
            next += 1
        }

        for (index, payer) in sortedPayers.enumerated() {
            let owed = shares[index]
            if owed > 0 { owedMinor.append((payer.person, owed)) }
            paidMinor.append((payer.person, payer.net + owed))
        }

        // Absorb any net rounding drift (cents that don't sum to zero in the
        // source) into the largest payer so payments total the cost exactly.
        let paidSum = paidMinor.reduce(0) { $0 + $1.amount }
        let drift = costMinor - paidSum
        if drift != 0, let largest = paidMinor.indices.max(by: { paidMinor[$0].amount < paidMinor[$1].amount }) {
            paidMinor[largest].amount += drift
            if abs(drift) > 2 {
                warnings.append(Warning(
                    line: line,
                    message: "Row's amounts didn't sum cleanly; adjusted by \(decimalString(drift, multiplier)) to balance."
                ))
            }
        }

        // Final guard: never emit an expense whose payments or splits don't sum
        // exactly to the total, or that has a negative share (the DB rejects it).
        let finalPaid = paidMinor.reduce(0) { $0 + $1.amount }
        let finalOwed = owedMinor.reduce(0) { $0 + $1.amount }
        guard finalPaid == costMinor, finalOwed == costMinor,
              paidMinor.allSatisfy({ $0.amount >= 0 }), owedMinor.allSatisfy({ $0.amount >= 0 })
        else {
            warnings.append(Warning(line: line, message: "Row's amounts don't balance; skipped."))
            return nil
        }

        let payments = paidMinor
            .filter { $0.amount > 0 }
            .map { Share(person: $0.person, amount: fromMinor($0.amount, multiplier)) }
        let splits = owedMinor
            .filter { $0.amount > 0 }
            .map { Share(person: $0.person, amount: fromMinor($0.amount, multiplier)) }
        return (payments, splits)
    }

    // MARK: - Primitive parsing

    /// Splits CSV text into records, preserving 1-based source line numbers.
    /// Handles `\r\n`, `\r`, and `\n`, and quoted fields containing commas
    /// (RFC 4180, single-line fields — Splitwise never embeds newlines in a
    /// field). Fully blank lines are kept here (callers skip them) so warnings
    /// can reference real line numbers.
    static func splitRecords(_ text: String) -> [(line: Int, fields: [String])] {
        var records: [(line: Int, fields: [String])] = []
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for (offset, rawLine) in normalized.components(separatedBy: "\n").enumerated() {
            if rawLine.isEmpty { continue }
            records.append((line: offset + 1, fields: parseFields(rawLine)))
        }
        return records
    }

    /// RFC 4180 field tokenizer for a single line.
    static func parseFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var pending: Character? = iterator.next()
        while let char = pending {
            pending = iterator.next()
            if inQuotes {
                if char == "\"" {
                    if pending == "\"" {            // escaped quote
                        current.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(char)
                }
            } else {
                switch char {
                case "\"": inQuotes = true
                case ",":
                    fields.append(current)
                    current = ""
                default:
                    current.append(char)
                }
            }
        }
        fields.append(current)
        return fields
    }

    /// Parses a plain signed decimal (`-12.34`). Rejects anything with grouping
    /// separators or stray characters rather than silently truncating a
    /// partially-parsed token (e.g. `1,234.56` would otherwise become `1`).
    static func parseDecimal(_ string: String) -> Decimal? {
        let cleaned = trimmed(string)
        guard isPlainDecimal(cleaned) else { return nil }
        return Decimal(string: cleaned, locale: posix)
    }

    private static func isPlainDecimal(_ string: String) -> Bool {
        var characters = Substring(string)
        if let first = characters.first, first == "-" || first == "+" {
            characters = characters.dropFirst()
        }
        guard !characters.isEmpty else { return false }
        var sawDot = false
        var sawDigit = false
        for character in characters {
            if character == "." {
                if sawDot { return false }
                sawDot = true
            } else if character >= "0" && character <= "9" {
                sawDigit = true
            } else {
                return false
            }
        }
        return sawDigit
    }

    /// `yyyy-MM-dd` -> the calendar day anchored at 12:00 UTC, matching tab's
    /// `expense_date` storage convention (`ExpenseDates`).
    static func parseDate(_ string: String) -> Date? {
        let parts = trimmed(string).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return utcCalendar.date(from: components)
    }

    // MARK: - Helpers

    private static func field(_ fields: [String], _ index: Int) -> String {
        index < fields.count ? trimmed(fields[index]) : ""
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func minorUnits(_ amount: Decimal, _ multiplier: Decimal) -> Int {
        var scaled = amount * multiplier
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return (rounded as NSDecimalNumber).intValue
    }

    private static func floorToInt(_ value: Decimal) -> Int {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .down)
        return (rounded as NSDecimalNumber).intValue
    }

    private static func fromMinor(_ minor: Int, _ multiplier: Decimal) -> Decimal {
        Decimal(minor) / multiplier
    }

    private static func decimalString(_ minor: Int, _ multiplier: Decimal) -> String {
        "\(fromMinor(minor, multiplier))"
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
