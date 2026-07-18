import Foundation

struct SettlementAmountDraft: Equatable, Sendable {
    private(set) var text = ""
    private(set) var wasUserEdited = false

    var shouldPrefill: Bool { !wasUserEdited }

    mutating func userChangedText(_ input: String, currency: String) {
        text = MoneyFormatter.sanitizeAmountInput(input, currency: currency)
        wasUserEdited = true
    }

    mutating func setProgrammaticText(_ value: String) {
        text = value
    }

    mutating func convert(to currency: String) {
        text = MoneyFormatter.convertAmountText(text, to: currency)
    }
}
