import Foundation
import TabCore

enum ExpensePaymentLedger {
    static func normalizedExactPayments(_ payments: [Payment], currency: String) -> [Payment] {
        payments.map { payment in
            guard payment.paymentMode == .exact else { return payment }
            let sourceText = NSDecimalNumber(decimal: payment.amountPaid).stringValue
            let rendered = MoneyFormatter.convertAmountText(sourceText, to: currency)
            guard let amount = MoneyFormatter.decimal(from: rendered) else { return payment }
            return Payment(payerID: payment.payerID, amountPaid: amount, paymentMode: payment.paymentMode)
        }
    }

    /// An empty ledger uses the default single payer at save time. An explicit
    /// ledger must balance and every entry must fit the selected currency.
    static func isValid(_ payments: [Payment], totalAmount: Decimal, currency: String) -> Bool {
        guard !payments.isEmpty else { return true }
        guard payments.allSatisfy({
            CurrencyCatalog.hasValidPrecision($0.amountPaid, currency: currency)
        }) else { return false }
        return payments.reduce(Decimal(0)) { $0 + $1.amountPaid } == totalAmount
    }
}
