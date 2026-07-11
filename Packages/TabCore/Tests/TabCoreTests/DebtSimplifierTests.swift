import Foundation
import Testing
@testable import TabCore

@Suite("DebtSimplifier")
struct DebtSimplifierTests {
    private let alice = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let bob = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let charlie = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let dev = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    @Test("a debt chain collapses to one payment")
    func chain() {
        let balances = mirrored(creditor: alice, debtor: bob, amount: 10)
            + mirrored(creditor: bob, debtor: charlie, amount: 10)

        #expect(DebtSimplifier.simplify(balances) == [
            SimplifiedDebt(fromUser: charlie, toUser: alice, currency: "EUR", amount: 10)
        ])
    }

    @Test("a closed cycle needs no payments")
    func cycle() {
        let balances = mirrored(creditor: alice, debtor: bob, amount: 10)
            + mirrored(creditor: bob, debtor: charlie, amount: 10)
            + mirrored(creditor: charlie, debtor: alice, amount: 10)

        #expect(DebtSimplifier.simplify(balances).isEmpty)
    }

    @Test("multiple creditors and debtors preserve every net position")
    func multiplePositions() {
        let balances = mirrored(creditor: alice, debtor: charlie, amount: 50)
            + mirrored(creditor: alice, debtor: dev, amount: 10)
            + mirrored(creditor: bob, debtor: dev, amount: 40)
        let simplified = DebtSimplifier.simplify(balances)

        #expect(simplified.count == 3)
        #expect(nets(of: simplified) == nets(of: balances))
    }

    @Test("currencies never mix")
    func currenciesStaySeparate() {
        let balances = mirrored(creditor: alice, debtor: bob, amount: 12, currency: "EUR")
            + mirrored(creditor: bob, debtor: charlie, amount: 12, currency: "EUR")
            + mirrored(creditor: dev, debtor: alice, amount: 900, currency: "JPY")

        let result = DebtSimplifier.simplify(balances)
        #expect(result == [
            SimplifiedDebt(fromUser: charlie, toUser: alice, currency: "EUR", amount: 12),
            SimplifiedDebt(fromUser: alice, toUser: dev, currency: "JPY", amount: 900),
        ])
    }

    @Test("pending people are ordinary ledger identities")
    func pendingPersonIncluded() {
        let pendingPerson = dev
        let balances = mirrored(creditor: pendingPerson, debtor: alice, amount: 25)

        #expect(DebtSimplifier.simplify(balances) == [
            SimplifiedDebt(fromUser: alice, toUser: pendingPerson, currency: "EUR", amount: 25)
        ])
    }

    @Test("decimal minor-unit values are preserved exactly")
    func decimalValues() {
        let balances = mirrored(creditor: alice, debtor: bob, amount: Decimal(string: "10.01")!)
            + mirrored(creditor: bob, debtor: charlie, amount: Decimal(string: "3.37")!)

        #expect(DebtSimplifier.simplify(balances) == [
            SimplifiedDebt(fromUser: bob, toUser: alice, currency: "EUR", amount: Decimal(string: "6.64")!),
            SimplifiedDebt(fromUser: charlie, toUser: alice, currency: "EUR", amount: Decimal(string: "3.37")!),
        ])
    }

    @Test("ties are deterministic regardless of input order")
    func deterministicTies() {
        let balances = mirrored(creditor: alice, debtor: charlie, amount: 10)
            + mirrored(creditor: bob, debtor: dev, amount: 10)

        let expected = DebtSimplifier.simplify(balances)
        #expect(DebtSimplifier.simplify(Array(balances.reversed())) == expected)
        #expect(expected == [
            SimplifiedDebt(fromUser: charlie, toUser: alice, currency: "EUR", amount: 10),
            SimplifiedDebt(fromUser: dev, toUser: bob, currency: "EUR", amount: 10),
        ])
    }

    private func mirrored(
        creditor: UUID,
        debtor: UUID,
        amount: Decimal,
        currency: String = "EUR"
    ) -> [UserBalance] {
        [
            UserBalance(forUser: creditor, withUser: debtor, currency: currency, amount: amount),
            UserBalance(forUser: debtor, withUser: creditor, currency: currency, amount: -amount),
        ]
    }

    private func nets(of balances: [UserBalance]) -> [UUID: Decimal] {
        var result: [UUID: Decimal] = [:]
        for row in balances where row.forUser.uuidString < row.withUser.uuidString {
            result[row.forUser, default: 0] += row.amount
            result[row.withUser, default: 0] -= row.amount
        }
        return result.filter { $0.value != 0 }
    }

    private func nets(of debts: [SimplifiedDebt]) -> [UUID: Decimal] {
        var result: [UUID: Decimal] = [:]
        for debt in debts {
            result[debt.toUser, default: 0] += debt.amount
            result[debt.fromUser, default: 0] -= debt.amount
        }
        return result.filter { $0.value != 0 }
    }
}
