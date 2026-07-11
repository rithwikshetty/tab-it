import Foundation

/// A trip person's spend on a trip, in one currency.
/// `paid` is what they fronted (payment ledger); `share` is what they consumed (split ledger).
public struct PersonSpend: Hashable, Sendable {
    public let personID: UUID
    public let paid: Decimal
    public let share: Decimal

    public init(personID: UUID, paid: Decimal, share: Decimal) {
        self.personID = personID
        self.paid = paid
        self.share = share
    }
}

/// Total spend attributed to one category, in one currency. `categoryID == nil` is uncategorized.
public struct CategorySpend: Hashable, Sendable {
    public let categoryID: UUID?
    public let total: Decimal

    public init(categoryID: UUID?, total: Decimal) {
        self.categoryID = categoryID
        self.total = total
    }
}

/// A per-trip spend summary for a single currency. Settlements are never included.
public struct TripSpendSummary: Hashable, Sendable {
    public let currency: String
    public let total: Decimal
    public let perPerson: [PersonSpend]
    public let perCategory: [CategorySpend]

    public init(
        currency: String,
        total: Decimal,
        perPerson: [PersonSpend],
        perCategory: [CategorySpend]
    ) {
        self.currency = currency
        self.total = total
        self.perPerson = perPerson
        self.perCategory = perCategory
    }
}

/// Pure derivation of per-trip *spend* (not balances) from a trip's expenses.
///
/// Spend is read from the two ledgers on each [[Expense]]: `paid` from payments, `share` from splits.
/// Settlements are intentionally not a parameter — they are debt-clearing, never trip spend.
/// Soft-deleted expenses are excluded. One [[TripSpendSummary]] is returned per currency present.
public enum TripAnalytics {
    public static func summarize(expenses: [Expense]) -> [TripSpendSummary] {
        let active = expenses.filter { $0.deletedAt == nil }
        let byCurrency = Dictionary(grouping: active) { $0.amount.currency }

        return byCurrency.keys.sorted().map { currency in
            let group = byCurrency[currency] ?? []
            let total = group.reduce(Decimal(0)) { $0 + $1.amount.amount }

            var paid: [UUID: Decimal] = [:]
            var share: [UUID: Decimal] = [:]
            for expense in group {
                for payment in expense.payments {
                    paid[payment.payerID, default: 0] += payment.amountPaid
                }
                for split in expense.splits {
                    share[split.participantID, default: 0] += split.amountOwed
                }
            }
            let perPerson = Set(paid.keys).union(share.keys)
                .map { PersonSpend(personID: $0, paid: paid[$0] ?? 0, share: share[$0] ?? 0) }
                .sorted { ($0.share, $0.personID.uuidString) > ($1.share, $1.personID.uuidString) }

            return TripSpendSummary(
                currency: currency,
                total: total,
                perPerson: perPerson,
                perCategory: categoryTotals(of: group)
            )
        }
    }

    /// Total per category across the given expenses, sorted high→low (uncategorized `nil` last on ties).
    private static func categoryTotals(of expenses: [Expense]) -> [CategorySpend] {
        var totals: [UUID?: Decimal] = [:]
        for expense in expenses {
            totals[expense.categoryID, default: 0] += expense.amount.amount
        }
        return totals
            .map { CategorySpend(categoryID: $0.key, total: $0.value) }
            .sorted {
                if $0.total != $1.total { return $0.total > $1.total }
                switch ($0.categoryID, $1.categoryID) {
                case (nil, _): return false
                case (_, nil): return true
                case let (lhs?, rhs?): return lhs.uuidString < rhs.uuidString
                }
            }
    }
}
