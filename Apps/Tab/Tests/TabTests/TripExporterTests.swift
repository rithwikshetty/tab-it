import Foundation
import SwiftData
import Testing
import TabCore
@testable import Tab

@MainActor
@Suite("Trip export")
struct TripExporterTests {
    @Test("extractData exports the expense's payment method, not the split mode")
    func extractDataUsesPaymentMethodNotMode() throws {
        let container = try TabModelContainer.makeInMemory()
        let ctx = container.mainContext

        let creatorID = UUID()
        let trip = TripEntity(name: "Tokyo", createdByID: creatorID)
        ctx.insert(trip)
        let alice = TripPersonEntity(
            id: UUID(), userID: creatorID, email: "alice@x.test", displayName: "Alice",
            invitedByID: creatorID, trip: trip, joinedAt: .now
        )
        ctx.insert(alice)

        let expense = ExpenseEntity(
            amount: 60, currency: "EUR", descriptionText: "Taxi",
            expenseDate: Date(timeIntervalSince1970: 1_780_000_000),
            paymentMethodRaw: "cash",          // the payment method
            createdByID: creatorID, trip: trip
        )
        ctx.insert(expense)
        ctx.insert(PaymentEntity(
            tripPersonID: alice.id, amountPaid: 60,
            paymentModeRaw: "equal",            // the split/payment mode
            expense: expense
        ))
        ctx.insert(ExpenseSplitEntity(
            tripPersonID: alice.id, amountOwed: 60, splitTypeRaw: "equal", expense: expense
        ))
        try ctx.save()

        let data = TripExporter.extractData(
            trip: trip,
            categories: [:],
            peopleByID: [alice.id: alice]
        )

        #expect(data.expenses.first?.paymentMethod == "cash")
        // The per-payment sheet carries the mode in its own column.
        #expect(data.expensePayments.first?.paymentMode == "equal")
    }

    @Test("workbook keeps expense overview readable and adds normalized payment and split sheets")
    func workbookHasNormalizedExpensePaymentAndSplitSheets() {
        let expenseID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let aliceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let bobID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let caraID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let data = TripExporter.ExportData(
            tripName: "Barcelona",
            expenses: [
                TripExporter.ExpenseRow(
                    id: expenseID.uuidString,
                    date: "2026-05-22",
                    description: "Dinner",
                    amount: 120,
                    currency: "EUR",
                    category: "Food",
                    paidBy: "Alice, Bob",
                    paidByDetail: "Alice: EUR 70.00; Bob: EUR 50.00",
                    splitBetween: "Alice, Bob, Cara",
                    splitDetail: "Alice: EUR 40.00; Bob: EUR 40.00; Cara: EUR 40.00",
                    paymentMethod: "card",
                    createdBy: "Alice",
                    createdAt: "2026-05-22 20:30",
                    lastEditedBy: "Cara",
                    lastEditedAt: "2026-05-22 21:00"
                )
            ],
            expensePayments: [
                TripExporter.ExpensePaymentRow(
                    expenseID: expenseID.uuidString,
                    date: "2026-05-22",
                    description: "Dinner",
                    payerID: aliceID.uuidString,
                    payerName: "Alice",
                    currency: "EUR",
                    amountPaid: 70,
                    paymentMode: "equal"
                ),
                TripExporter.ExpensePaymentRow(
                    expenseID: expenseID.uuidString,
                    date: "2026-05-22",
                    description: "Dinner",
                    payerID: bobID.uuidString,
                    payerName: "Bob",
                    currency: "EUR",
                    amountPaid: 50,
                    paymentMode: "equal"
                )
            ],
            expenseSplits: [
                TripExporter.ExpenseSplitRow(
                    expenseID: expenseID.uuidString,
                    date: "2026-05-22",
                    description: "Dinner",
                    participantID: aliceID.uuidString,
                    participantName: "Alice",
                    currency: "EUR",
                    amountOwed: 40,
                    splitType: "equal"
                ),
                TripExporter.ExpenseSplitRow(
                    expenseID: expenseID.uuidString,
                    date: "2026-05-22",
                    description: "Dinner",
                    participantID: bobID.uuidString,
                    participantName: "Bob",
                    currency: "EUR",
                    amountOwed: 40,
                    splitType: "equal"
                ),
                TripExporter.ExpenseSplitRow(
                    expenseID: expenseID.uuidString,
                    date: "2026-05-22",
                    description: "Dinner",
                    participantID: caraID.uuidString,
                    participantName: "Cara",
                    currency: "EUR",
                    amountOwed: 40,
                    splitType: "equal"
                )
            ],
            settlements: [],
            summary: TripExporter.Summary(
                totalsByCurrency: [TripExporter.CurrencyTotal(currency: "EUR", total: 120)],
                personSummaries: [],
                pairBalances: []
            )
        )

        let workbook = TripExporter.buildWorkbook(from: data)

        #expect(workbook.sheets.map(\.name) == [
            "Expenses",
            "Expense Payments",
            "Expense Splits",
            "Settlements",
            "Summary"
        ])

        let expenses = workbook.sheets[0].rows
        #expect(expenses[0].strings == [
            "Expense ID", "Date", "Description", "Amount", "Currency", "Category",
            "Paid By", "Paid By Detail", "Split Between", "Split Detail", "Payment Method",
            "Created By", "Created At", "Last Edited By", "Last Edited At"
        ])
        #expect(expenses[1].strings[6] == "Alice, Bob")
        #expect(expenses[1].strings[7] == "Alice: EUR 70.00; Bob: EUR 50.00")
        #expect(expenses[1].strings[8] == "Alice, Bob, Cara")
        #expect(expenses[1].strings[9] == "Alice: EUR 40.00; Bob: EUR 40.00; Cara: EUR 40.00")

        let payments = workbook.sheets[1].rows
        #expect(payments.count == 3)
        #expect(payments[0].strings == [
            "Expense ID", "Date", "Description", "Payer ID", "Payer Name",
            "Currency", "Amount Paid", "Payment Mode"
        ])
        #expect(payments[1].strings[3] == aliceID.uuidString)
        #expect(payments[1].strings[4] == "Alice")

        let splits = workbook.sheets[2].rows
        #expect(splits.count == 4)
        #expect(splits[0].strings == [
            "Expense ID", "Date", "Description", "Participant ID", "Participant Name",
            "Currency", "Amount Owed", "Split Type"
        ])
        #expect(splits[3].strings[3] == caraID.uuidString)
        #expect(splits[3].strings[4] == "Cara")
    }
}

private extension Array where Element == TripExporter.WorkbookCell {
    var strings: [String] {
        map { cell in
            switch cell {
            case .string(let value): value
            case .number(let value): value.description
            }
        }
    }
}

@Suite("Settle up prefill")
struct SettleUpPrefillTests {
    private let trip = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!
    private let alice = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let bob = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    private let cara = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!

    @Test("prefill suggests the largest debtor to the current user after many expenses and partial settlements")
    func suggestsLargestDebtorToCurrentUser() throws {
        let expenses = (0..<6).map { index in
            makeExpense(
                id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-00000000010\(index)")!,
                payer: alice,
                amount: 120,
                currency: "EUR",
                participants: [alice, bob, cara]
            )
        }
        let settlements = [
            makeSettlement(from: bob, to: alice, amount: 210, currency: "EUR"),
            makeSettlement(from: cara, to: alice, amount: 70, currency: "EUR"),
        ]
        // Bob has almost cleared his debt; Cara is now the largest remaining debtor.
        let balances = BalanceEngine.compute(expenses: expenses, settlements: settlements)

        let suggestion = try #require(SettleUpPresenter.suggestedPayment(
            balances: balances,
            currentPersonID: alice
        ))

        #expect(suggestion.fromPersonID == cara)
        #expect(suggestion.toPersonID == alice)
        #expect(suggestion.amount == 170)
        #expect(suggestion.currency == "EUR")
    }

    @Test("prefill uses the current user's redirected trip-wide balance")
    func suggestsRedirectedTripWideBalance() throws {
        let expenses = [
            makeExpense(
                id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000201")!,
                payer: alice,
                amount: 300,
                currency: "EUR",
                participants: [alice, cara]
            ),
            makeExpense(
                id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000202")!,
                payer: bob,
                amount: 30,
                currency: "EUR",
                participants: [alice, bob]
            ),
        ]
        let balances = BalanceEngine.compute(expenses: expenses, settlements: [])

        let suggestion = try #require(SettleUpPresenter.suggestedPayment(
            balances: balances,
            currentPersonID: alice
        ))

        #expect(suggestion.fromPersonID == cara)
        #expect(suggestion.toPersonID == alice)
        #expect(suggestion.amount == 135)
        #expect(suggestion.currency == "EUR")
    }

    @Test("prefill redirects a debt through an intermediary")
    func suggestsCrossSettledRedirect() throws {
        let balances = [
            UserBalance(forUser: bob, withUser: alice, currency: "EUR", amount: 10),
            UserBalance(forUser: alice, withUser: bob, currency: "EUR", amount: -10),
            UserBalance(forUser: cara, withUser: bob, currency: "EUR", amount: 10),
            UserBalance(forUser: bob, withUser: cara, currency: "EUR", amount: -10),
        ]

        let suggestion = try #require(SettleUpPresenter.suggestedPayment(
            balances: balances,
            currentPersonID: alice
        ))

        #expect(suggestion.fromPersonID == alice)
        #expect(suggestion.toPersonID == cara)
        #expect(suggestion.amount == 10)
        #expect(suggestion.currency == "EUR")
    }

    private func makeExpense(
        id: UUID,
        payer: UUID,
        amount: Decimal,
        currency: String,
        participants: [UUID]
    ) -> Expense {
        let share = amount / Decimal(participants.count)
        return Expense(
            id: id,
            tripID: trip,
            amount: Money(amount: amount, currency: currency),
            descriptionText: "Shared cost",
            expenseDate: Date(timeIntervalSince1970: 1_780_000_000),
            payments: [
                Payment(payerID: payer, amountPaid: amount, paymentMode: .equal),
            ],
            splits: participants.map {
                ExpenseSplit(participantID: $0, amountOwed: share, splitType: .equal)
            },
            createdBy: payer,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    private func makeSettlement(
        from: UUID,
        to: UUID,
        amount: Decimal,
        currency: String
    ) -> Settlement {
        Settlement(
            tripID: trip,
            fromUserID: from,
            toUserID: to,
            amount: Money(amount: amount, currency: currency),
            settledAt: Date(timeIntervalSince1970: 1_780_000_000),
            createdBy: alice,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }
}
