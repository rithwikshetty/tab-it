import Foundation

struct MemberCard: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    let initial: String
    let tone: AvatarTone

    init(id: UUID, displayName: String, avatarName: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.initial = AvatarInitial.from(avatarName ?? displayName)
        self.tone = AvatarTone.deterministic(for: id)
    }
}

struct TripCard: Identifiable, Hashable, Sendable {
    enum Status: Hashable, Sendable {
        case owed(String)
        case owe(String)
        case mixed(String)
        case settled(String)
        case empty
    }

    let id: UUID
    let name: String
    let members: [MemberCard]
    let status: Status
    let isCompleted: Bool
}

struct ExpenseRowItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let categoryID: UUID?
    let icon: String
    let name: String
    let payerName: String
    let totalAmount: String
    let yourShare: String
    let netAmount: String?
    let balanceSemantic: BalanceSemantic
    var sourceName: String? = nil
}

struct ExpenseDay: Identifiable, Hashable, Sendable {
    let id: String
    let dateLabel: String
    let expenses: [ExpenseRowItem]
}

struct BalanceDetailItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let counterparty: String
    let amount: String
    let semantic: BalanceSemantic
}

struct BalanceSummary: Hashable, Sendable {
    let label: String
    let amount: String
    let details: [BalanceDetailItem]
    let semantic: BalanceSemantic
}

enum BalanceSemantic: Hashable, Sendable {
    case lent
    case borrowed
    case neutral
}

struct SimplifiedDebtGroup: Identifiable, Hashable, Sendable {
    var id: String { currency }
    let currency: String
    let debts: [SimplifiedDebtRowItem]
}

struct SimplifiedDebtRowItem: Identifiable, Hashable, Sendable {
    let id: String
    let fromName: String
    let toName: String
    let amount: String
    let semantic: BalanceSemantic
    let suggestion: SettleUpSuggestion
}

struct CategoryOption: Identifiable, Hashable, Sendable {
    let id: UUID
    let icon: String
    let name: String
}

struct SettlementRowItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let fromName: String
    let toName: String
    let formattedAmount: String
    let text: String
    var sourceName: String? = nil
}

struct SettleUpSuggestion: Hashable, Sendable {
    let fromPersonID: UUID
    let toPersonID: UUID
    let amount: Decimal
    let currency: String
}

enum TimelineItem: Identifiable, Hashable, Sendable {
    case expense(ExpenseRowItem)
    case settlement(SettlementRowItem)

    var id: UUID {
        switch self {
        case .expense(let e): e.id
        case .settlement(let s): s.id
        }
    }
}

struct TimelineDay: Identifiable, Hashable, Sendable {
    let id: String
    let dateLabel: String
    let totals: [TimelineDayTotal]
    let items: [TimelineItem]
}

struct TimelineDayTotal: Identifiable, Hashable, Sendable {
    var id: String { currency }
    let currency: String
    let totalSpend: String
    let yourShare: String
}

// MARK: - Overview (per-trip spend)

struct OverviewState: Hashable, Sendable {
    /// Currencies present in active expenses, sorted. Picker is shown only when `count > 1`.
    let currencies: [String]
    /// One page per currency, same order as `currencies`. Empty when the trip has no expenses.
    let pages: [OverviewPage]

    var isEmpty: Bool { pages.isEmpty }

    /// Placeholder used before a trip's derived state has been computed.
    static let empty = OverviewState(currencies: [], pages: [])
}

struct OverviewPage: Identifiable, Hashable, Sendable {
    var id: String { currency }
    let currency: String
    let totalSpent: String
    let youPaid: String
    let yourShare: String
    /// e.g. "26% of trip spend". Nil when total is zero.
    let yourSharePercent: String?
    let people: [OverviewPersonRow]
    let categories: [OverviewCategoryRow]
}

struct OverviewPersonRow: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let isYou: Bool
    let paid: String
    let share: String
    /// share / total, for the share-of-trip mini bar (0...1).
    let shareFraction: Double
}

struct OverviewCategoryRow: Identifiable, Hashable, Sendable {
    let id: String
    let categoryID: UUID?
    let name: String
    let amount: String
    /// Share of trip total (0...1), for the "39%" readout.
    let percent: Double
    /// Width relative to the largest category (0...1), for the bar.
    let fraction: Double
}
