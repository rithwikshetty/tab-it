import Foundation
import Testing
import TabCore
@testable import Tab

@MainActor
@Suite("Payment split draft")
struct PaymentSplitDraftTests {
    private let alice = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let bob = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    @Test("removing the last extra payer in exact mode leaves a valid single payer")
    func exactModeUntoggleToOnePayerStaysValid() {
        let draft = PaymentSplitDraft()
        draft.selectedPayerIDs = [alice, bob]
        draft.setPayerMode(.exact, totalAmount: 100, currency: "USD")
        // The user edits an amount (so payerEdited becomes true), then removes Bob.
        draft.setExactPayerAmount("30", for: bob, currency: "USD")
        draft.togglePayer(bob, totalAmount: 100, currency: "USD")

        #expect(draft.selectedPayerIDs == [alice])
        // The lone remaining payer must resolve to a payable ledger, not a dead end.
        let payments = draft.computedPayments(totalAmount: 100, currency: "USD")
        #expect(payments != nil)
        #expect(payments?.count == 1)
        #expect(payments?.first?.amountPaid == 100)
    }

    @Test("a single exact payer covers the full total")
    func singleExactPayerCoversTotal() {
        let draft = PaymentSplitDraft()
        draft.selectedPayerIDs = [alice, bob]
        draft.setPayerMode(.exact, totalAmount: 80, currency: "USD")
        draft.togglePayer(bob, totalAmount: 80, currency: "USD")
        #expect(draft.computedPayments(totalAmount: 80, currency: "USD")?.first?.amountPaid == 80)
    }

    @Test("switching to shares seeds every participant with 1 share")
    func sharesModeSeedsOnes() {
        let draft = PaymentSplitDraft()
        draft.selectedParticipants = [alice, bob]
        draft.setSplitMode(2, totalAmount: 30, currency: "USD")

        #expect(draft.shareSplitText[alice] == "1")
        #expect(draft.shareSplitText[bob] == "1")
        let splits = draft.computedSplits(totalAmount: 30, currency: "USD")
        #expect(splits?.count == 2)
        #expect(splits?.allSatisfy { $0.amountOwed == 15 } == true)
    }

    @Test("shares mode: weights drive the split and survive on the result")
    func sharesModeWeightedSplit() {
        let draft = PaymentSplitDraft()
        draft.selectedParticipants = [alice, bob]
        draft.setSplitMode(2, totalAmount: 30, currency: "USD")
        draft.setShareSplitText("2", for: alice)
        draft.setShareSplitText("0.5", for: bob)

        let splits = draft.computedSplits(totalAmount: 30, currency: "USD")
        let byUser = Dictionary(uniqueKeysWithValues: (splits ?? []).map { ($0.participantID, $0) })
        #expect(byUser[alice]?.amountOwed == 24)
        #expect(byUser[bob]?.amountOwed == 6)
        #expect(byUser[alice]?.shareUnits == 2)
        #expect(byUser[bob]?.shareUnits == Decimal(string: "0.5"))
    }

    @Test("shares mode: an emptied share field blocks the split")
    func sharesModeEmptyShareBlocks() {
        let draft = PaymentSplitDraft()
        draft.selectedParticipants = [alice, bob]
        draft.setSplitMode(2, totalAmount: 30, currency: "USD")
        draft.setShareSplitText("", for: bob)

        #expect(draft.computedSplits(totalAmount: 30, currency: "USD") == nil)
    }

    @Test("shares mode: toggling in a new participant seeds their share")
    func sharesModeToggleSeedsNewParticipant() {
        let draft = PaymentSplitDraft()
        draft.selectedParticipants = [alice]
        draft.setSplitMode(2, totalAmount: 30, currency: "USD")
        draft.toggleParticipant(bob, totalAmount: 30, currency: "USD")

        #expect(draft.shareSplitText[bob] == "1")
        #expect(draft.computedSplits(totalAmount: 30, currency: "USD")?.count == 2)
    }

    @Test("switching to percentages seeds an equal 100% starting point")
    func percentModeSeedsEqual() {
        let draft = PaymentSplitDraft()
        draft.selectedParticipants = [alice, bob]
        draft.setSplitMode(3, totalAmount: 80, currency: "USD")

        #expect(draft.percentSplitText[alice] == "50")
        #expect(draft.percentSplitText[bob] == "50")
        let splits = draft.computedSplits(totalAmount: 80, currency: "USD")
        #expect(splits?.count == 2)
        #expect(splits?.allSatisfy { $0.amountOwed == 40 } == true)
    }

    @Test("percentage mode: weights drive the split and survive on the result")
    func percentModeWeightedSplit() {
        let draft = PaymentSplitDraft()
        draft.selectedParticipants = [alice, bob]
        draft.setSplitMode(3, totalAmount: 80, currency: "USD")
        draft.setPercentSplitText("75", for: alice)
        draft.setPercentSplitText("25", for: bob)

        let splits = draft.computedSplits(totalAmount: 80, currency: "USD")
        let byUser = Dictionary(uniqueKeysWithValues: (splits ?? []).map { ($0.participantID, $0) })
        #expect(byUser[alice]?.amountOwed == 60)
        #expect(byUser[bob]?.amountOwed == 20)
        #expect(byUser[alice]?.percentage == 75)
        #expect(byUser[bob]?.percentage == 25)
    }

    @Test("percentage mode: totals that are not 100 block the split")
    func percentModeMustSumTo100() {
        let draft = PaymentSplitDraft()
        draft.selectedParticipants = [alice, bob]
        draft.setSplitMode(3, totalAmount: 80, currency: "USD")
        draft.setPercentSplitText("75", for: alice)
        draft.setPercentSplitText("24", for: bob)

        #expect(draft.computedSplits(totalAmount: 80, currency: "USD") == nil)
    }
}

@Suite("Expense payment ledger")
struct ExpensePaymentLedgerTests {
    private let alice = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let bob = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    @Test("currency changes re-render committed exact payment amounts")
    func exactPaymentsFollowCurrencyPrecision() {
        let payments = [
            Payment(payerID: alice, amountPaid: Decimal(string: "600.25")!, paymentMode: .exact),
            Payment(payerID: bob, amountPaid: Decimal(string: "400.25")!, paymentMode: .exact),
        ]

        let normalized = ExpensePaymentLedger.normalizedExactPayments(payments, currency: "JPY")

        #expect(normalized.map(\.amountPaid) == [600, 400])
        #expect(normalized.allSatisfy { $0.paymentMode == .exact })
    }

    @Test("every payment must match the selected currency precision")
    func individualPaymentPrecisionIsValidated() {
        let invalid = [
            Payment(payerID: alice, amountPaid: Decimal(string: "600.5")!, paymentMode: .exact),
            Payment(payerID: bob, amountPaid: Decimal(string: "399.5")!, paymentMode: .exact),
        ]
        let valid = [
            Payment(payerID: alice, amountPaid: 600, paymentMode: .exact),
            Payment(payerID: bob, amountPaid: 400, paymentMode: .exact),
        ]

        #expect(!ExpensePaymentLedger.isValid(invalid, totalAmount: 1000, currency: "JPY"))
        #expect(ExpensePaymentLedger.isValid(valid, totalAmount: 1000, currency: "JPY"))
    }
}
