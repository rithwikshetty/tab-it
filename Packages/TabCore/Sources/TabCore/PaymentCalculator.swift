import Foundation

public enum PaymentCalculatorError: Error, Equatable, Sendable {
    case emptyPayers
    case duplicatePayer(UUID)
    case unsupportedPaymentMode(PaymentMode)
    case exactAmountsRequired
    case missingAmountForPayer(UUID)
    case extraAmountForNonPayer(UUID)
    case amountHasTooManyFractionDigits(currency: String, maximumFractionDigits: Int)
    case amountsDoNotSumToTotal(expected: Decimal, actual: Decimal)
}

public enum PaymentCalculator {
    public static func calculate(
        totalAmount: Decimal,
        currency: String,
        payers: [UUID],
        paymentMode: PaymentMode,
        exactAmounts: [UUID: Decimal]? = nil
    ) throws -> [Payment] {
        guard !payers.isEmpty else {
            throw PaymentCalculatorError.emptyPayers
        }

        switch paymentMode {
        case .equal:
            let splits = try delegate(
                totalAmount: totalAmount,
                currency: currency,
                participants: payers,
                splitType: .equal,
                exactAmounts: nil
            )
            return splits.map {
                Payment(payerID: $0.participantID, amountPaid: $0.amountOwed, paymentMode: .equal)
            }

        case .exact:
            guard let amounts = exactAmounts else {
                throw PaymentCalculatorError.exactAmountsRequired
            }
            let splits = try delegate(
                totalAmount: totalAmount,
                currency: currency,
                participants: payers,
                splitType: .exact,
                exactAmounts: amounts
            )
            return splits.map {
                Payment(payerID: $0.participantID, amountPaid: $0.amountOwed, paymentMode: .exact)
            }

        case .percentage, .shares, .adjustment:
            throw PaymentCalculatorError.unsupportedPaymentMode(paymentMode)
        }
    }

    private static func delegate(
        totalAmount: Decimal,
        currency: String,
        participants: [UUID],
        splitType: SplitType,
        exactAmounts: [UUID: Decimal]?
    ) throws -> [ExpenseSplit] {
        do {
            return try SplitCalculator.calculate(
                totalAmount: totalAmount,
                currency: currency,
                participants: participants,
                splitType: splitType,
                exactAmounts: exactAmounts
            )
        } catch let err as SplitCalculatorError {
            throw map(err)
        }
    }

    private static func map(_ err: SplitCalculatorError) -> PaymentCalculatorError {
        switch err {
        case .emptyParticipants:
            return .emptyPayers
        case .duplicateParticipant(let id):
            return .duplicatePayer(id)
        case .unsupportedSplitType(let type):
            return .unsupportedPaymentMode(type)
        case .exactAmountsRequired:
            return .exactAmountsRequired
        case .missingAmountForParticipant(let id):
            return .missingAmountForPayer(id)
        case .extraAmountForNonParticipant(let id):
            return .extraAmountForNonPayer(id)
        case .amountHasTooManyFractionDigits(let currency, let maximumFractionDigits):
            return .amountHasTooManyFractionDigits(
                currency: currency,
                maximumFractionDigits: maximumFractionDigits
            )
        case .amountsDoNotSumToTotal(let expected, let actual):
            return .amountsDoNotSumToTotal(expected: expected, actual: actual)
        case .sharesRequired, .missingShareForParticipant, .extraShareForNonParticipant, .nonPositiveShare:
            // Unreachable: payments only delegate equal/exact splits.
            return .unsupportedPaymentMode(.shares)
        case .percentagesRequired, .missingPercentageForParticipant, .extraPercentageForNonParticipant,
             .nonPositivePercentage, .percentagesDoNotSumTo100:
            // Unreachable: payments only delegate equal/exact splits.
            return .unsupportedPaymentMode(.percentage)
        }
    }
}
