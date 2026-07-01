import Foundation

public enum SplitCalculatorError: Error, Equatable, Sendable {
    case emptyParticipants
    case duplicateParticipant(UUID)
    case unsupportedSplitType(SplitType)
    case exactAmountsRequired
    case missingAmountForParticipant(UUID)
    case extraAmountForNonParticipant(UUID)
    case amountHasTooManyFractionDigits(currency: String, maximumFractionDigits: Int)
    case amountsDoNotSumToTotal(expected: Decimal, actual: Decimal)
    case sharesRequired
    case missingShareForParticipant(UUID)
    case extraShareForNonParticipant(UUID)
    case nonPositiveShare(UUID)
    case percentagesRequired
    case missingPercentageForParticipant(UUID)
    case extraPercentageForNonParticipant(UUID)
    case nonPositivePercentage(UUID)
    case percentagesDoNotSumTo100(actual: Decimal)
}

public enum SplitCalculator {
    public static func calculate(
        totalAmount: Decimal,
        currency: String,
        participants: [UUID],
        splitType: SplitType,
        exactAmounts: [UUID: Decimal]? = nil,
        shares: [UUID: Decimal]? = nil,
        percentages: [UUID: Decimal]? = nil
    ) throws -> [ExpenseSplit] {
        guard !participants.isEmpty else {
            throw SplitCalculatorError.emptyParticipants
        }

        var seen = Set<UUID>()
        for participant in participants where !seen.insert(participant).inserted {
            throw SplitCalculatorError.duplicateParticipant(participant)
        }

        try validatePrecision(totalAmount, currency: currency)

        switch splitType {
        case .equal:
            return calculateEqual(total: totalAmount, currency: currency, participants: participants)
        case .exact:
            guard let amounts = exactAmounts else {
                throw SplitCalculatorError.exactAmountsRequired
            }
            return try calculateExact(total: totalAmount, currency: currency, participants: participants, amounts: amounts)
        case .shares:
            guard let shares else {
                throw SplitCalculatorError.sharesRequired
            }
            return try calculateShares(total: totalAmount, currency: currency, participants: participants, shares: shares)
        case .percentage:
            guard let percentages else {
                throw SplitCalculatorError.percentagesRequired
            }
            return try calculatePercentages(total: totalAmount, currency: currency, participants: participants, percentages: percentages)
        case .adjustment:
            throw SplitCalculatorError.unsupportedSplitType(splitType)
        }
    }

    /// Equal percentages at 2 fraction digits that sum to exactly 100; the
    /// leftover basis points go to the lexicographically lowest UUIDs (the
    /// same convention as equal-split remainders). Used to seed percentage UI.
    public static func equalPercentages(participants: [UUID]) -> [UUID: Decimal] {
        guard !participants.isEmpty else { return [:] }
        let totalBasisPoints = 10_000
        let base = totalBasisPoints / participants.count
        let remainder = totalBasisPoints % participants.count
        let sorted = participants.sorted { $0.uuidString < $1.uuidString }
        var result: [UUID: Decimal] = [:]
        for (index, id) in sorted.enumerated() {
            result[id] = Decimal(base + (index < remainder ? 1 : 0)) / 100
        }
        return result
    }

    // Distributes `total` evenly at the smallest supported unit for the currency.
    // Any remainder is assigned one minor unit at a time to the lowest sorted UUIDs.
    private static func calculateEqual(total: Decimal, currency: String, participants: [UUID]) -> [ExpenseSplit] {
        let n = Decimal(participants.count)
        let multiplier = CurrencyCatalog.minorUnitMultiplier(for: currency)
        let totalMinorUnits = roundToInteger(total * multiplier)
        let baseMinorUnits = roundDownToInteger(totalMinorUnits / n)
        let baseShare = baseMinorUnits / multiplier
        let remainderUnits = totalMinorUnits - baseMinorUnits * n

        let extraCount = (remainderUnits as NSDecimalNumber).intValue
        let sortedIDs = participants.sorted { $0.uuidString < $1.uuidString }
        let bonusIDs = Set(sortedIDs.prefix(extraCount))

        let smallestUnit = Decimal(1) / multiplier
        return participants.map { id in
            let owed = bonusIDs.contains(id) ? (baseShare + smallestUnit) : baseShare
            return ExpenseSplit(participantID: id, amountOwed: owed, splitType: .equal)
        }
    }

    private static func calculateExact(
        total: Decimal,
        currency: String,
        participants: [UUID],
        amounts: [UUID: Decimal]
    ) throws -> [ExpenseSplit] {
        let participantSet = Set(participants)

        for key in amounts.keys where !participantSet.contains(key) {
            throw SplitCalculatorError.extraAmountForNonParticipant(key)
        }
        for participant in participants where amounts[participant] == nil {
            throw SplitCalculatorError.missingAmountForParticipant(participant)
        }

        for amount in amounts.values {
            try validatePrecision(amount, currency: currency)
        }

        let sum = amounts.values.reduce(Decimal(0), +)
        if sum != total {
            throw SplitCalculatorError.amountsDoNotSumToTotal(expected: total, actual: sum)
        }

        return participants.map { id in
            ExpenseSplit(participantID: id, amountOwed: amounts[id]!, splitType: .exact)
        }
    }

    private static func calculateShares(
        total: Decimal,
        currency: String,
        participants: [UUID],
        shares: [UUID: Decimal]
    ) throws -> [ExpenseSplit] {
        let participantSet = Set(participants)

        for key in shares.keys where !participantSet.contains(key) {
            throw SplitCalculatorError.extraShareForNonParticipant(key)
        }
        for participant in participants where shares[participant] == nil {
            throw SplitCalculatorError.missingShareForParticipant(participant)
        }
        for participant in participants.sorted(by: { $0.uuidString < $1.uuidString }) where shares[participant]! <= 0 {
            throw SplitCalculatorError.nonPositiveShare(participant)
        }

        let amounts = allocateProportionally(total: total, currency: currency, participants: participants, weights: shares)
        return participants.map { id in
            ExpenseSplit(participantID: id, amountOwed: amounts[id]!, splitType: .shares, shareUnits: shares[id])
        }
    }

    private static func calculatePercentages(
        total: Decimal,
        currency: String,
        participants: [UUID],
        percentages: [UUID: Decimal]
    ) throws -> [ExpenseSplit] {
        let participantSet = Set(participants)

        for key in percentages.keys where !participantSet.contains(key) {
            throw SplitCalculatorError.extraPercentageForNonParticipant(key)
        }
        for participant in participants where percentages[participant] == nil {
            throw SplitCalculatorError.missingPercentageForParticipant(participant)
        }
        for participant in participants.sorted(by: { $0.uuidString < $1.uuidString }) where percentages[participant]! <= 0 {
            throw SplitCalculatorError.nonPositivePercentage(participant)
        }

        let sum = participants.reduce(Decimal(0)) { $0 + percentages[$1]! }
        if sum != 100 {
            throw SplitCalculatorError.percentagesDoNotSumTo100(actual: sum)
        }

        let amounts = allocateProportionally(total: total, currency: currency, participants: participants, weights: percentages)
        return participants.map { id in
            ExpenseSplit(participantID: id, amountOwed: amounts[id]!, splitType: .percentage, percentage: percentages[id])
        }
    }

    // Weight-proportional allocation at the smallest supported unit for the
    // currency. Each participant gets floor(total * weight / weightSum) minor
    // units; the leftover units go out one at a time by largest fractional
    // remainder, tie-broken by lexicographically lowest UUID (deterministic,
    // like equal). Weights must be positive and non-empty (callers validate).
    private static func allocateProportionally(
        total: Decimal,
        currency: String,
        participants: [UUID],
        weights: [UUID: Decimal]
    ) -> [UUID: Decimal] {
        let weightSum = participants.reduce(Decimal(0)) { $0 + weights[$1]! }
        let multiplier = CurrencyCatalog.minorUnitMultiplier(for: currency)
        let totalMinorUnits = roundToInteger(total * multiplier)

        var floorMinorUnits: [UUID: Decimal] = [:]
        var fractionalParts: [UUID: Decimal] = [:]
        var floorSum = Decimal(0)
        for id in participants {
            let ideal = totalMinorUnits * weights[id]! / weightSum
            let floored = roundDownToInteger(ideal)
            floorMinorUnits[id] = floored
            fractionalParts[id] = ideal - floored
            floorSum += floored
        }

        // Largest fractional remainder first; UUID breaks ties.
        let order = participants.sorted { a, b in
            if fractionalParts[a]! != fractionalParts[b]! {
                return fractionalParts[a]! > fractionalParts[b]!
            }
            return a.uuidString < b.uuidString
        }

        var remaining = ((totalMinorUnits - floorSum) as NSDecimalNumber).intValue
        for id in order where remaining > 0 {
            floorMinorUnits[id]! += 1
            remaining -= 1
        }
        // Decimal division rounding at precision limits could in principle push
        // a floor one unit high; claw back so the splits always sum to total.
        for id in order.reversed() where remaining < 0 {
            if floorMinorUnits[id]! > 0 {
                floorMinorUnits[id]! -= 1
                remaining += 1
            }
        }

        return floorMinorUnits.mapValues { $0 / multiplier }
    }

    private static func validatePrecision(_ amount: Decimal, currency: String) throws {
        guard CurrencyCatalog.hasValidPrecision(amount, currency: currency) else {
            throw SplitCalculatorError.amountHasTooManyFractionDigits(
                currency: CurrencyCatalog.normalizedCode(currency),
                maximumFractionDigits: CurrencyCatalog.fractionDigits(for: currency)
            )
        }
    }

    private static func roundToInteger(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }

    private static func roundDownToInteger(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .down)
        return result
    }
}
