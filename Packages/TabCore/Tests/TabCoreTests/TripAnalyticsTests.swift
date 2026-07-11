import Testing
import Foundation
@testable import TabCore

@Suite("TripAnalytics")
struct TripAnalyticsTests {
    let alice = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let bob = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    let charlie = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!
    let food = UUID(uuidString: "00000000-0000-0000-0000-0000000000F0")!
    let lodging = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!

    // MARK: empty

    @Test("no expenses → no summaries")
    func empty() {
        #expect(TripAnalytics.summarize(expenses: []).isEmpty)
    }

    // MARK: single expense → total + currency

    @Test("one expense → one summary carrying total and currency")
    func singleExpenseTotal() throws {
        let expense = makeExpense(
            amount: 30, currency: "EUR", category: food,
            payments: [Payment(payerID: alice, amountPaid: 30, paymentMode: .equal)],
            splits: [split(alice, 15), split(bob, 15)]
        )
        let summaries = TripAnalytics.summarize(expenses: [expense])
        #expect(summaries.count == 1)
        let s = try #require(summaries.first)
        #expect(s.currency == "EUR")
        #expect(s.total == 30)
    }

    // MARK: per-person paid vs share

    @Test("multi-payer expense → each person's paid and share read from the two ledgers")
    func perPersonPaidAndShare() throws {
        // €120: Alice fronted 70, Bob fronted 50; split equally 3 ways (40 each).
        let expense = makeExpense(
            amount: 120, currency: "EUR", category: food,
            payments: [
                Payment(payerID: alice, amountPaid: 70, paymentMode: .exact),
                Payment(payerID: bob, amountPaid: 50, paymentMode: .exact),
            ],
            splits: [split(alice, 40), split(bob, 40), split(charlie, 40)]
        )
        let s = try #require(TripAnalytics.summarize(expenses: [expense]).first)

        func person(_ id: UUID) throws -> PersonSpend {
            try #require(s.perPerson.first { $0.personID == id })
        }
        #expect(try person(alice).paid == 70)
        #expect(try person(alice).share == 40)
        #expect(try person(bob).paid == 50)
        #expect(try person(bob).share == 40)
        // Charlie paid nothing but still consumed a share.
        #expect(try person(charlie).paid == 0)
        #expect(try person(charlie).share == 40)
    }

    // MARK: total invariant

    @Test("total equals both summed paid and summed share")
    func totalMatchesBothLedgers() throws {
        let expenses = [
            makeExpense(
                amount: 90, currency: "EUR", category: food,
                payments: [Payment(payerID: alice, amountPaid: 90, paymentMode: .equal)],
                splits: [split(alice, 30), split(bob, 30), split(charlie, 30)]
            ),
            makeExpense(
                amount: 50, currency: "EUR", category: lodging,
                payments: [
                    Payment(payerID: bob, amountPaid: 20, paymentMode: .exact),
                    Payment(payerID: charlie, amountPaid: 30, paymentMode: .exact),
                ],
                splits: [split(bob, 25), split(charlie, 25)]
            ),
        ]
        let s = try #require(TripAnalytics.summarize(expenses: expenses).first)
        let summedPaid = s.perPerson.reduce(Decimal(0)) { $0 + $1.paid }
        let summedShare = s.perPerson.reduce(Decimal(0)) { $0 + $1.share }
        #expect(s.total == 140)
        #expect(summedPaid == 140)
        #expect(summedShare == 140)
    }

    // MARK: multi-currency

    @Test("expenses in different currencies → one summary each, never summed together")
    func multiCurrencyPartitioned() throws {
        let expenses = [
            makeExpense(
                amount: 100, currency: "EUR", category: food,
                payments: [Payment(payerID: alice, amountPaid: 100, paymentMode: .equal)],
                splits: [split(alice, 100)]
            ),
            makeExpense(
                amount: 8000, currency: "JPY", category: lodging,
                payments: [Payment(payerID: bob, amountPaid: 8000, paymentMode: .equal)],
                splits: [split(bob, 8000)]
            ),
        ]
        let summaries = TripAnalytics.summarize(expenses: expenses)
        #expect(summaries.count == 2)
        // Sorted by currency code: EUR before JPY.
        #expect(summaries.map(\.currency) == ["EUR", "JPY"])
        #expect(try #require(summaries.first { $0.currency == "EUR" }).total == 100)
        #expect(try #require(summaries.first { $0.currency == "JPY" }).total == 8000)
    }

    // MARK: per-category

    @Test("per-category totals aggregate across expenses, include uncategorized, sorted high→low")
    func perCategoryAggregated() throws {
        let expenses = [
            makeExpense(amount: 40, currency: "EUR", category: food,
                        payments: [Payment(payerID: alice, amountPaid: 40, paymentMode: .equal)],
                        splits: [split(alice, 40)]),
            makeExpense(amount: 60, currency: "EUR", category: food,
                        payments: [Payment(payerID: alice, amountPaid: 60, paymentMode: .equal)],
                        splits: [split(alice, 60)]),
            makeExpense(amount: 200, currency: "EUR", category: lodging,
                        payments: [Payment(payerID: alice, amountPaid: 200, paymentMode: .equal)],
                        splits: [split(alice, 200)]),
            makeExpense(amount: 25, currency: "EUR", category: nil,
                        payments: [Payment(payerID: alice, amountPaid: 25, paymentMode: .equal)],
                        splits: [split(alice, 25)]),
        ]
        let s = try #require(TripAnalytics.summarize(expenses: expenses).first)
        #expect(s.perCategory == [
            CategorySpend(categoryID: lodging, total: 200),
            CategorySpend(categoryID: food, total: 100),
            CategorySpend(categoryID: nil, total: 25),
        ])
    }

    @Test("per-category ties: uncategorized sorts last")
    func perCategoryTieUncategorizedLast() throws {
        let expenses = [
            makeExpense(amount: 50, currency: "EUR", category: nil,
                        payments: [Payment(payerID: alice, amountPaid: 50, paymentMode: .equal)],
                        splits: [split(alice, 50)]),
            makeExpense(amount: 50, currency: "EUR", category: food,
                        payments: [Payment(payerID: alice, amountPaid: 50, paymentMode: .equal)],
                        splits: [split(alice, 50)]),
        ]
        let s = try #require(TripAnalytics.summarize(expenses: expenses).first)
        #expect(s.perCategory == [
            CategorySpend(categoryID: food, total: 50),
            CategorySpend(categoryID: nil, total: 50),
        ])
    }

    // MARK: soft delete

    @Test("soft-deleted expenses are excluded from totals, people, and categories")
    func softDeletedExcluded() throws {
        let active = makeExpense(amount: 40, currency: "EUR", category: food,
                                 payments: [Payment(payerID: alice, amountPaid: 40, paymentMode: .equal)],
                                 splits: [split(alice, 40)])
        let deleted = makeExpense(amount: 999, currency: "EUR", category: lodging, date: day(2026, 4, 1),
                                  payments: [Payment(payerID: bob, amountPaid: 999, paymentMode: .equal)],
                                  splits: [split(bob, 999)],
                                  deletedAt: day(2026, 4, 2))
        let s = try #require(TripAnalytics.summarize(expenses: [active, deleted]).first)
        #expect(s.total == 40)
        #expect(s.perCategory == [CategorySpend(categoryID: food, total: 40)])
        #expect(s.perPerson.contains { $0.personID == bob } == false)
    }

    // MARK: helpers

    private let trip = UUID()

    private func split(_ person: UUID, _ amount: Decimal) -> ExpenseSplit {
        ExpenseSplit(participantID: person, amountOwed: amount, splitType: .equal)
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        DateComponents(calendar: .current, year: y, month: m, day: d, hour: 12).date!
    }

    private func makeExpense(
        amount: Decimal,
        currency: String,
        category: UUID? = nil,
        date: Date? = nil,
        payments: [Payment],
        splits: [ExpenseSplit],
        deletedAt: Date? = nil
    ) -> Expense {
        let now = date ?? day(2026, 3, 14)
        return Expense(
            tripID: trip,
            amount: Money(amount: amount, currency: currency),
            categoryID: category,
            expenseDate: now,
            payments: payments,
            splits: splits,
            createdBy: alice,
            createdAt: now,
            updatedAt: now,
            deletedAt: deletedAt
        )
    }
}
