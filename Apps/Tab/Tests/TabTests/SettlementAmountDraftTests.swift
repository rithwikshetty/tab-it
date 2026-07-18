import Testing
@testable import Tab

@Suite("Settlement amount prefill")
struct SettlementAmountDraftTests {
    @Test("untouched amount can be prefilled")
    func untouchedAmountCanBePrefilled() {
        let draft = SettlementAmountDraft()

        #expect(draft.shouldPrefill)
    }

    @Test("typed amount cannot be replaced by a prefill")
    func typedAmountCannotBePrefilled() {
        var draft = SettlementAmountDraft()
        draft.userChangedText("25.50", currency: "EUR")

        #expect(draft.text == "25.50")
        #expect(!draft.shouldPrefill)
    }

    @Test("typed amount stays user-edited after currency conversion")
    func typedAmountStaysEditedAfterCurrencyChange() {
        var draft = SettlementAmountDraft()
        draft.userChangedText("25.50", currency: "EUR")
        draft.convert(to: "JPY")

        #expect(draft.text == "26")
        #expect(!draft.shouldPrefill)
    }

    @Test("clearing a prefilled amount counts as a user edit")
    func clearedAmountCannotBePrefilled() {
        var draft = SettlementAmountDraft()
        draft.setProgrammaticText("40.00")
        draft.userChangedText("", currency: "EUR")

        #expect(draft.text.isEmpty)
        #expect(!draft.shouldPrefill)
    }
}
