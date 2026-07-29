import Foundation
import Testing
@testable import TabCore

private struct ParityFixture: Decodable {
    struct SplitCase: Decodable {
        let name: String
        let total: String
        let currency: String
        let participants: [UUID]
        let expected: [String]
    }

    struct BalanceCase: Decodable {
        struct Entry: Decodable {
            let person: UUID
            let amount: String
        }

        struct Expected: Decodable {
            let `for`: UUID
            let with: UUID
            let amount: String
        }

        let name: String
        let currency: String
        let total: String
        let payments: [Entry]
        let splits: [Entry]
        let expected: [Expected]
    }

    struct TripStateCase: Decodable {
        let name: String
        let lastActivity: Date
        let now: Date
        let hasBalance: Bool
        let expected: String
    }

    let splitCases: [SplitCase]
    let balanceCases: [BalanceCase]
    let tripStateCases: [TripStateCase]
}

@Suite("Android/iOS shared parity fixture")
struct ParityFixtureTests {
    private let fixture: ParityFixture

    init() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "contracts/domain/parity-v1.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        fixture = try decoder.decode(ParityFixture.self, from: Data(contentsOf: fixtureURL))
    }

    @Test("equal splits match shared fixture")
    func equalSplits() throws {
        for item in fixture.splitCases {
            let result = try SplitCalculator.calculate(
                totalAmount: Decimal(string: item.total)!,
                currency: item.currency,
                participants: item.participants,
                splitType: .equal
            )
            #expect(result.map(\.amountOwed) == item.expected.map { Decimal(string: $0)! }, Comment(rawValue: item.name))
        }
    }

    @Test("balances match shared fixture")
    func balances() {
        let time = Date(timeIntervalSince1970: 1_767_268_800)
        let trip = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        for item in fixture.balanceCases {
            let payments = item.payments.map {
                Payment(payerID: $0.person, amountPaid: Decimal(string: $0.amount)!, paymentMode: .exact)
            }
            let splits = item.splits.map {
                ExpenseSplit(participantID: $0.person, amountOwed: Decimal(string: $0.amount)!, splitType: .exact)
            }
            let expense = Expense(
                tripID: trip,
                amount: Money(amount: Decimal(string: item.total)!, currency: item.currency),
                expenseDate: time,
                payments: payments,
                splits: splits,
                createdBy: payments[0].payerID,
                createdAt: time,
                updatedAt: time
            )
            let actual = BalanceEngine.compute(expenses: [expense], settlements: []).filter { $0.amount > 0 }
            #expect(actual.count == item.expected.count, Comment(rawValue: item.name))
            for (actualRow, expectedRow) in zip(actual, item.expected) {
                #expect(actualRow.forUser == expectedRow.for)
                #expect(actualRow.withUser == expectedRow.with)
                #expect(actualRow.currency == item.currency)
                #expect(actualRow.amount == Decimal(string: expectedRow.amount)!)
            }
        }
    }

    @Test("trip states match shared fixture")
    func tripStates() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        for item in fixture.tripStateCases {
            let balances = item.hasBalance
                ? [UserBalance(forUser: first, withUser: second, currency: "GBP", amount: 1)]
                : []
            let actual = TripStateDeriver.derive(
                balances: balances,
                lastActivityAt: item.lastActivity,
                now: item.now
            )
            #expect(String(describing: actual) == item.expected, Comment(rawValue: item.name))
        }
    }
}
