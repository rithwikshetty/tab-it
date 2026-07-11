import Foundation

/// One derived payment that helps clear a trip while preserving every person's net position.
/// `fromUser` pays `toUser`; simplified debts are never persisted as a second ledger.
public struct SimplifiedDebt: Hashable, Sendable {
    public let fromUser: UUID
    public let toUser: UUID
    public let currency: String
    public let amount: Decimal

    public init(fromUser: UUID, toUser: UUID, currency: String, amount: Decimal) {
        self.fromUser = fromUser
        self.toUser = toUser
        self.currency = currency
        self.amount = amount
    }
}

/// Deterministically reduces pairwise `BalanceEngine` output to trip-wide repayment suggestions.
public enum DebtSimplifier {
    public static func simplify(_ balances: [UserBalance]) -> [SimplifiedDebt] {
        var netByCurrency: [String: [UUID: Decimal]] = [:]

        // BalanceEngine emits mirrored rows. Read only the lexicographically lower
        // person's perspective so each pair contributes exactly once.
        for balance in balances
        where balance.forUser.uuidString < balance.withUser.uuidString && balance.amount != 0 {
            netByCurrency[balance.currency, default: [:]][balance.forUser, default: 0] += balance.amount
            netByCurrency[balance.currency, default: [:]][balance.withUser, default: 0] -= balance.amount
        }

        var result: [SimplifiedDebt] = []
        for currency in netByCurrency.keys.sorted() {
            let positions = netByCurrency[currency] ?? [:]
            var creditors = positions.compactMap { id, amount in
                amount > 0 ? Position(id: id, amount: amount) : nil
            }
            var debtors = positions.compactMap { id, amount in
                amount < 0 ? Position(id: id, amount: -amount) : nil
            }

            while !creditors.isEmpty && !debtors.isEmpty {
                creditors.sort(by: Position.precedes)
                debtors.sort(by: Position.precedes)

                let amount = min(creditors[0].amount, debtors[0].amount)
                guard amount > 0 else { break }

                result.append(SimplifiedDebt(
                    fromUser: debtors[0].id,
                    toUser: creditors[0].id,
                    currency: currency,
                    amount: amount
                ))

                creditors[0].amount -= amount
                debtors[0].amount -= amount
                creditors.removeAll { $0.amount == 0 }
                debtors.removeAll { $0.amount == 0 }
            }
        }
        return result
    }

    private struct Position {
        let id: UUID
        var amount: Decimal

        static func precedes(_ lhs: Position, _ rhs: Position) -> Bool {
            if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
