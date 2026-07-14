import Foundation
import Testing
@testable import Tab

@MainActor
@Suite("Balance presenter")
struct BalancePresenterTests {
    private let you = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let sam = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let alex = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test("tied balance detail rows use a stable display-name tie-breaker")
    func tiedDetailRowsSortByDisplayName() throws {
        let trip = TripEntity(name: "Demo", createdByID: you)
        let people = [
            person(id: you, name: "You", trip: trip),
            person(id: sam, name: "Sam", trip: trip),
            person(id: alex, name: "Alex", trip: trip),
        ]
        let expense = ExpenseEntity(
            amount: 90,
            currency: "GBP",
            descriptionText: "Dinner",
            expenseDate: Date(timeIntervalSince1970: 1_780_000_000),
            createdByID: you,
            trip: trip
        )
        expense.payments = [
            PaymentEntity(tripPersonID: you, amountPaid: 90, paymentModeRaw: "equal", expense: expense)
        ]
        expense.splits = [
            ExpenseSplitEntity(tripPersonID: you, amountOwed: 30, splitTypeRaw: "equal", expense: expense),
            ExpenseSplitEntity(tripPersonID: sam, amountOwed: 30, splitTypeRaw: "equal", expense: expense),
            ExpenseSplitEntity(tripPersonID: alex, amountOwed: 30, splitTypeRaw: "equal", expense: expense),
        ]

        let peopleByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        let summary = try #require(BalancePresenter.summaries(
            expenses: [expense],
            settlements: [],
            people: people,
            currentPersonID: you,
            personFor: { peopleByID[$0] }
        ).first)

        #expect(summary.details.map(\.counterparty) == ["Alex owes you", "Sam owes you"])
        #expect(summary.details.map(\.amount) == [
            MoneyFormatter.format(30, currency: "GBP"),
            MoneyFormatter.format(30, currency: "GBP"),
        ])
        #expect(summary.semantic == .lent)
    }

    @Test("summary detail rows follow simplified debts, not raw pairwise balances")
    func summaryDetailsUseSimplifiedDebts() throws {
        let trip = TripEntity(name: "Demo", createdByID: you)
        let people = [
            person(id: you, name: "You", trip: trip),
            person(id: sam, name: "Sam", trip: trip),
            person(id: alex, name: "Alex", trip: trip),
        ]
        // You owe Sam 30 and Sam owes Alex 30, so the simplified repayment
        // is a single "You owe Alex" — the raw pairwise view would say Sam.
        let dinner = ExpenseEntity(
            amount: 30,
            currency: "GBP",
            descriptionText: "Dinner",
            expenseDate: Date(timeIntervalSince1970: 1_780_000_000),
            createdByID: you,
            trip: trip
        )
        dinner.payments = [
            PaymentEntity(tripPersonID: sam, amountPaid: 30, paymentModeRaw: "equal", expense: dinner)
        ]
        dinner.splits = [
            ExpenseSplitEntity(tripPersonID: you, amountOwed: 30, splitTypeRaw: "equal", expense: dinner)
        ]
        let taxi = ExpenseEntity(
            amount: 30,
            currency: "GBP",
            descriptionText: "Taxi",
            expenseDate: Date(timeIntervalSince1970: 1_780_000_000),
            createdByID: you,
            trip: trip
        )
        taxi.payments = [
            PaymentEntity(tripPersonID: alex, amountPaid: 30, paymentModeRaw: "equal", expense: taxi)
        ]
        taxi.splits = [
            ExpenseSplitEntity(tripPersonID: sam, amountOwed: 30, splitTypeRaw: "equal", expense: taxi)
        ]

        let peopleByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        let summary = try #require(BalancePresenter.summaries(
            expenses: [dinner, taxi],
            settlements: [],
            people: people,
            currentPersonID: you,
            personFor: { peopleByID[$0] }
        ).first)

        #expect(summary.label == "You owe")
        #expect(summary.amount == MoneyFormatter.format(30, currency: "GBP"))
        #expect(summary.semantic == .borrowed)
        #expect(summary.details.map(\.counterparty) == ["You owe Alex"])
        #expect(summary.details.map(\.semantic) == [.borrowed])
    }

    @Test("simplified groups expose debts between other and pending trip people")
    func simplifiedTripWideDebts() throws {
        let pending = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let trip = TripEntity(name: "Demo", createdByID: you)
        let people = [
            person(id: you, name: "You", trip: trip),
            person(id: sam, name: "Sam", trip: trip),
            TripPersonEntity(id: pending, email: "pending@example.com", displayName: "Priya", trip: trip),
        ]
        let expense = ExpenseEntity(
            amount: 90,
            currency: "GBP",
            descriptionText: "Hotel",
            expenseDate: Date(timeIntervalSince1970: 1_780_000_000),
            createdByID: you,
            trip: trip
        )
        expense.payments = [
            PaymentEntity(tripPersonID: pending, amountPaid: 90, paymentModeRaw: "equal", expense: expense)
        ]
        expense.splits = [
            ExpenseSplitEntity(tripPersonID: sam, amountOwed: 90, splitTypeRaw: "equal", expense: expense)
        ]
        let peopleByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })

        let group = try #require(BalancePresenter.simplifiedGroups(
            expenses: [expense],
            settlements: [],
            currentPersonID: you,
            personFor: { peopleByID[$0] }
        ).first)
        let debt = try #require(group.debts.first)

        #expect(debt.fromName == "Sam")
        #expect(debt.toName == "Priya")
        #expect(debt.semantic == .neutral)
        #expect(debt.suggestion == SettleUpSuggestion(
            fromPersonID: sam,
            toPersonID: pending,
            amount: 90,
            currency: "GBP"
        ))
    }

    private func person(id: UUID, name: String, trip: TripEntity) -> TripPersonEntity {
        TripPersonEntity(
            id: id,
            email: "\(name.lowercased())@example.com",
            displayName: name,
            trip: trip,
            joinedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }
}
