import Foundation
import Testing
@testable import Tab

/// `expense_date` is a calendar date, not an instant. The contract: whatever
/// day the user saw in the picker is the day that gets stored, pushed,
/// pulled, and displayed — regardless of their timezone or time of day.
@Suite("Expense dates")
struct ExpenseDatesTests {
    private func calendar(_ tzID: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tzID)!
        return c
    }

    private func instant(_ y: Int, _ m: Int, _ d: Int, hour: Int, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    @Test("evening expense west of UTC keeps the user's calendar day")
    func eveningWestOfUTC() {
        // 6pm June 10 in Los Angeles is already June 11 in UTC — the bug case.
        let cal = calendar("America/Los_Angeles")
        let picked = instant(2026, 6, 10, hour: 18, in: cal)
        let anchored = ExpenseDates.utcNoonAnchor(forLocalDay: picked, calendar: cal)
        #expect(ExpenseDates.serialized(anchored) == "2026-06-10")
    }

    @Test("morning expense east of UTC keeps the user's calendar day")
    func morningEastOfUTC() {
        // 8am June 10 in Sydney is June 9 in UTC.
        let cal = calendar("Australia/Sydney")
        let picked = instant(2026, 6, 10, hour: 8, in: cal)
        let anchored = ExpenseDates.utcNoonAnchor(forLocalDay: picked, calendar: cal)
        #expect(ExpenseDates.serialized(anchored) == "2026-06-10")
    }

    @Test("anchoring is idempotent — re-saving an already-anchored date keeps the day")
    func anchorIdempotent() {
        let cal = calendar("America/Los_Angeles")
        let picked = instant(2026, 6, 10, hour: 18, in: cal)
        let once = ExpenseDates.utcNoonAnchor(forLocalDay: picked, calendar: cal)
        let twice = ExpenseDates.utcNoonAnchor(forLocalDay: once, calendar: cal)
        #expect(once == twice)
    }

    @Test("anchor round-trips through the pull-side parser")
    func anchorMatchesPullConvention() {
        let cal = calendar("Europe/Lisbon")
        let picked = instant(2026, 12, 31, hour: 23, in: cal)
        let anchored = ExpenseDates.utcNoonAnchor(forLocalDay: picked, calendar: cal)
        // Pull parses yyyy-MM-dd at UTC noon; the anchor must already be that instant.
        var utc = Calendar(identifier: .iso8601)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour], from: anchored)
        #expect(parts.year == 2026 && parts.month == 12 && parts.day == 31)
        #expect(parts.hour == 12)
    }
}

@MainActor
@Suite("Expense timeline presentation")
struct ExpenseTimelinePresenterTests {
    private let you = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let alex = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test("rows show viewer share and lending direction while day totals stay per currency")
    func sharesAndDailyTotals() throws {
        let date = DateComponents(calendar: .current, year: 2026, month: 7, day: 10, hour: 12).date!
        let borrowed = expense(
            amount: 100,
            currency: "THB",
            date: date,
            viewerPaid: 0,
            viewerShare: 40,
            otherPaid: 100,
            otherShare: 60,
            createdAt: date.addingTimeInterval(1)
        )
        let lent = expense(
            amount: 50,
            currency: "THB",
            date: date,
            viewerPaid: 50,
            viewerShare: 20,
            otherPaid: 0,
            otherShare: 30,
            createdAt: date.addingTimeInterval(2)
        )
        let noShare = expense(
            amount: 10,
            currency: "USD",
            date: date,
            viewerPaid: 0,
            viewerShare: 0,
            otherPaid: 10,
            otherShare: 10,
            createdAt: date.addingTimeInterval(3)
        )
        let settlement = SettlementEntity(
            fromPersonID: you,
            toPersonID: alex,
            amount: 999,
            currency: "THB",
            settledAt: date,
            createdByID: you,
            createdAt: date.addingTimeInterval(4)
        )

        let day = try #require(TimelinePresenter.days(
            expenses: [borrowed, lent, noShare],
            settlements: [settlement],
            currentPersonID: you,
            personFor: { _ in nil },
            categoryFor: { _ in nil }
        ).first)

        #expect(day.totals == [
            TimelineDayTotal(
                currency: "THB",
                totalSpend: MoneyFormatter.format(150, currency: "THB"),
                yourShare: MoneyFormatter.format(60, currency: "THB")
            ),
            TimelineDayTotal(
                currency: "USD",
                totalSpend: MoneyFormatter.format(10, currency: "USD"),
                yourShare: MoneyFormatter.format(0, currency: "USD")
            ),
        ])

        let expenseRows = day.items.compactMap { item -> ExpenseRowItem? in
            guard case .expense(let row) = item else { return nil }
            return row
        }
        let lentRow = try #require(expenseRows.first { $0.id == lent.id })
        #expect(lentRow.yourShare == MoneyFormatter.format(20, currency: "THB"))
        #expect(lentRow.totalAmount == MoneyFormatter.format(50, currency: "THB"))
        #expect(lentRow.netAmount == MoneyFormatter.format(30, currency: "THB"))
        #expect(lentRow.balanceSemantic == .lent)

        let borrowedRow = try #require(expenseRows.first { $0.id == borrowed.id })
        #expect(borrowedRow.yourShare == MoneyFormatter.format(40, currency: "THB"))
        #expect(borrowedRow.netAmount == MoneyFormatter.format(40, currency: "THB"))
        #expect(borrowedRow.balanceSemantic == .borrowed)

        let zeroRow = try #require(expenseRows.first { $0.id == noShare.id })
        #expect(zeroRow.yourShare == MoneyFormatter.format(0, currency: "USD"))
        #expect(zeroRow.totalAmount == MoneyFormatter.format(10, currency: "USD"))
        #expect(zeroRow.balanceSemantic == .neutral)
        #expect(zeroRow.netAmount == nil)
    }

    private func expense(
        amount: Decimal,
        currency: String,
        date: Date,
        viewerPaid: Decimal,
        viewerShare: Decimal,
        otherPaid: Decimal,
        otherShare: Decimal,
        createdAt: Date
    ) -> ExpenseEntity {
        let expense = ExpenseEntity(
            amount: amount,
            currency: currency,
            descriptionText: "Expense",
            expenseDate: date,
            createdByID: you,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        expense.payments = [
            PaymentEntity(tripPersonID: you, amountPaid: viewerPaid, paymentModeRaw: "exact", expense: expense),
            PaymentEntity(tripPersonID: alex, amountPaid: otherPaid, paymentModeRaw: "exact", expense: expense),
        ].filter { $0.amountPaid > 0 }
        expense.splits = [
            ExpenseSplitEntity(tripPersonID: you, amountOwed: viewerShare, splitTypeRaw: "exact", expense: expense),
            ExpenseSplitEntity(tripPersonID: alex, amountOwed: otherShare, splitTypeRaw: "exact", expense: expense),
        ].filter { $0.amountOwed > 0 }
        return expense
    }
}
