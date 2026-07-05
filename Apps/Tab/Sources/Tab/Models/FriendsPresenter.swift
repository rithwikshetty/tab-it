import Foundation
import TabCore

// MARK: - Friends view-state

/// One currency's gross totals across all friends, for the Friends-tab banner.
struct FriendsOverallLine: Identifiable, Hashable, Sendable {
    var id: String { currency }
    let currency: String
    let youAreOwed: Decimal   // sum of balances where friends owe the current user
    let youOwe: Decimal       // sum (positive) of balances the current user owes
}

/// One currency line of a friend's net balance with the current user.
struct FriendAmountLine: Identifiable, Hashable, Sendable {
    var id: String { currency }
    let currency: String
    /// "owes you" when the friend owes the current user, else "you owe".
    let label: String
    let amount: String        // formatted, unsigned (e.g. "£6.35")
    let isPositive: Bool      // friend owes you (sage) vs you owe (warn)
}

/// A person the current user shares any container with.
struct FriendRow: Identifiable, Hashable, Sendable {
    let id: String            // canonical identity key
    let friend: FriendIdentity
    let displayName: String
    let initial: String
    let tone: AvatarTone
    let isPending: Bool       // not yet signed in (email-only)
    let subtitle: String      // e.g. "Non-group + 2 trips"
    let lines: [FriendAmountLine]   // per currency, non-zero only
    var isSettled: Bool { lines.isEmpty }
}

struct FriendsListState: Hashable, Sendable {
    let overall: [FriendsOverallLine]
    let active: [FriendRow]    // at least one non-zero balance
    let settled: [FriendRow]   // all settled
    var isEmpty: Bool { active.isEmpty && settled.isEmpty }
}

/// One source's contribution to a friend balance — a tappable settle target.
struct FriendSourceRow: Identifiable, Hashable, Sendable {
    var id: String { containerID.uuidString + currency }
    let containerID: UUID
    let sourceName: String     // trip name, or "Non-group"
    let isNonGroup: Bool
    let currency: String
    let label: String          // "you owe" / "owes you"
    let amount: String
    let isPositive: Bool
}

struct FriendTimelineEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceName: String
    let item: TimelineItem
}

struct FriendTimelineDay: Identifiable, Hashable, Sendable {
    let id: String
    let dateLabel: String
    let entries: [FriendTimelineEntry]
}

struct FriendDetailState: Hashable, Sendable {
    let friend: FriendIdentity
    let displayName: String
    let initial: String
    let tone: AvatarTone
    let isPending: Bool
    let overall: [FriendAmountLine]      // per-currency net
    let sources: [FriendSourceRow]       // per (container, currency), non-zero
    let timeline: [FriendTimelineDay]
}

/// App-level mirror of `TabCore.ClaimIdentity`, `Codable`-free and carried in nav routes.
enum FriendIdentity: Hashable, Sendable {
    case user(UUID)
    case email(String)

    init(_ claim: ClaimIdentity) {
        switch claim {
        case .user(let id): self = .user(id)
        case .email(let e): self = .email(e)
        }
    }

    var claim: ClaimIdentity {
        switch self {
        case .user(let id): return .user(id)
        case .email(let e): return .email(e)
        }
    }

    var key: String {
        switch self {
        case .user(let id): return "u:" + id.uuidString
        case .email(let e): return "e:" + e
        }
    }

    var isPending: Bool { if case .email = self { return true }; return false }
}

// MARK: - Presenter

@MainActor
enum FriendsPresenter {

    static func list(trips: [TripEntity], currentUserID: UUID) -> FriendsListState {
        let ctx = Context(trips: trips, currentUserID: currentUserID)
        let me = ClaimIdentity.user(currentUserID)
        let myBalances = ctx.overall.filter { $0.forIdentity == me }

        // Friend candidates = current members of my containers, plus removed
        // people who still owe or are owed something, minus me.
        var friendClaims = ctx.activeClaims
        for balance in myBalances where balance.amount != 0 {
            friendClaims.insert(balance.withIdentity)
        }
        friendClaims.subtract([me])

        var rows: [FriendRow] = []
        for claim in friendClaims {
            let lines = amountLines(myBalances.filter { $0.withIdentity == claim })
            rows.append(FriendRow(
                id: claim.canonicalKey,
                friend: FriendIdentity(claim),
                displayName: ctx.displayName(for: claim),
                initial: AvatarInitial.from(ctx.displayName(for: claim)),
                tone: tone(for: claim),
                isPending: FriendIdentity(claim).isPending,
                subtitle: ctx.sourceSummary(for: claim),
                lines: lines
            ))
        }

        let active = rows.filter { !$0.isSettled }.sorted(by: friendSort)
        let settled = rows.filter { $0.isSettled }.sorted(by: friendSort)

        // Banner totals per currency.
        var owed: [String: Decimal] = [:]
        var owe: [String: Decimal] = [:]
        for b in myBalances where b.amount != 0 {
            if b.amount > 0 { owed[b.currency, default: 0] += b.amount }
            else { owe[b.currency, default: 0] += -b.amount }
        }
        let overall = Set(owed.keys).union(owe.keys).sorted().map {
            FriendsOverallLine(currency: $0, youAreOwed: owed[$0] ?? 0, youOwe: owe[$0] ?? 0)
        }

        return FriendsListState(overall: overall, active: active, settled: settled)
    }

    static func detail(trips: [TripEntity], currentUserID: UUID, friend: FriendIdentity) -> FriendDetailState? {
        let ctx = Context(trips: trips, currentUserID: currentUserID)
        let me = ClaimIdentity.user(currentUserID)
        let claim = friend.claim
        guard claim != me else { return nil }

        let myBalances = ctx.overall.filter { $0.forIdentity == me && $0.withIdentity == claim }
        let overall = amountLines(myBalances)

        // Per-source breakdown (tappable settle targets).
        let sourceBalances = OverallBalanceAggregator.breakdown(
            ctx.containers, identityMap: ctx.identityMap, for: me, with: claim
        )
        let sources: [FriendSourceRow] = sourceBalances.compactMap { src in
            guard let trip = ctx.trip(src.containerID) else { return nil }
            return FriendSourceRow(
                containerID: src.containerID,
                sourceName: ctx.sourceName(trip),
                isNonGroup: trip.isNonGroup,
                currency: src.currency,
                label: src.amount > 0 ? "owes you" : "you owe",
                amount: MoneyFormatter.formatSymbol(abs(src.amount), currency: src.currency),
                isPositive: src.amount > 0
            )
        }

        let timeline = sharedTimeline(ctx: ctx, friend: claim, currentUserID: currentUserID)

        return FriendDetailState(
            friend: friend,
            displayName: ctx.displayName(for: claim),
            initial: AvatarInitial.from(ctx.displayName(for: claim)),
            tone: tone(for: claim),
            isPending: friend.isPending,
            overall: overall,
            sources: sources,
            timeline: timeline
        )
    }

    // MARK: - Shared computation context

    private struct Context {
        let trips: [TripEntity]
        let currentUserID: UUID
        let containers: [ContainerBalances]
        let identityMap: [UUID: ClaimIdentity]
        /// Claims with at least one non-removed person row. Removed people
        /// stay in identityMap (their balances and history must resolve) but
        /// only surface as friends while something is still owed.
        let activeClaims: Set<ClaimIdentity>
        let overall: [OverallBalance]
        private let tripsByID: [UUID: TripEntity]
        private let peopleByClaim: [String: [TripPersonEntity]]  // canonicalKey -> rows

        init(trips: [TripEntity], currentUserID: UUID) {
            let me = ClaimIdentity.user(currentUserID)
            let active = trips.filter { trip in
                trip.deletedAt == nil
                    && trip.people.contains { ClaimIdentity.resolve(userID: $0.userID, email: $0.email) == me }
            }
            self.trips = active
            self.currentUserID = currentUserID
            self.tripsByID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            var map: [UUID: ClaimIdentity] = [:]
            var byClaim: [String: [TripPersonEntity]] = [:]
            var activeSet: Set<ClaimIdentity> = []
            for trip in active {
                for p in trip.people {
                    let claim = ClaimIdentity.resolve(userID: p.userID, email: p.email)
                    map[p.id] = claim
                    byClaim[claim.canonicalKey, default: []].append(p)
                    if p.removedAt == nil { activeSet.insert(claim) }
                }
            }
            self.identityMap = map
            self.peopleByClaim = byClaim
            self.activeClaims = activeSet

            self.containers = active.map { trip in
                let expenses = trip.expenses.filter { $0.deletedAt == nil }.map { $0.toCoreExpense() }
                let settlements = trip.settlements.filter { $0.deletedAt == nil }.map { $0.toCoreSettlement() }
                return ContainerBalances(
                    containerID: trip.id,
                    balances: BalanceEngine.compute(expenses: expenses, settlements: settlements)
                )
            }
            self.overall = OverallBalanceAggregator.aggregate(self.containers, identityMap: map)
        }

        func trip(_ id: UUID) -> TripEntity? { tripsByID[id] }

        func sourceName(_ trip: TripEntity) -> String { trip.isNonGroup ? "Non-group" : trip.name }

        func displayName(for claim: ClaimIdentity) -> String {
            // Prefer a claimed person's name; otherwise any non-empty; else the email.
            let rows = peopleByClaim[claim.canonicalKey] ?? []
            if let named = rows.first(where: { !$0.displayName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty }) {
                return named.displayName
            }
            if case .email(let e) = claim { return e }
            return "Member"
        }

        /// e.g. "Non-group + 2 trips" or "Goa".
        func sourceSummary(for claim: ClaimIdentity) -> String {
            var names: [String] = []
            var hasNonGroup = false
            for trip in trips where trip.people.contains(where: { ClaimIdentity.resolve(userID: $0.userID, email: $0.email) == claim }) {
                if trip.isNonGroup { hasNonGroup = true } else { names.append(trip.name) }
            }
            var parts: [String] = []
            if hasNonGroup { parts.append("Non-group") }
            if names.count == 1 { parts.append(names[0]) }
            else if names.count > 1 { parts.append("\(names.count) trips") }
            return parts.joined(separator: " + ")
        }

        func personID(in trip: TripEntity, claim: ClaimIdentity) -> UUID? {
            trip.people.first { ClaimIdentity.resolve(userID: $0.userID, email: $0.email) == claim }?.id
        }
    }

    // MARK: - Helpers

    private static func amountLines(_ balances: [OverallBalance]) -> [FriendAmountLine] {
        balances.filter { $0.amount != 0 }
            .sorted { $0.currency < $1.currency }
            .map { b in
                FriendAmountLine(
                    currency: b.currency,
                    label: b.amount > 0 ? "owes you" : "you owe",
                    amount: MoneyFormatter.formatSymbol(abs(b.amount), currency: b.currency),
                    isPositive: b.amount > 0
                )
            }
    }

    private static func friendSort(_ a: FriendRow, _ b: FriendRow) -> Bool {
        a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
    }

    static func tone(for claim: ClaimIdentity) -> AvatarTone {
        switch claim {
        case .user(let id):
            return AvatarTone.deterministic(for: id)
        case .email(let e):
            return AvatarTone.deterministic(forEmail: e)
        }
    }

    private static func sharedTimeline(ctx: Context, friend: ClaimIdentity, currentUserID: UUID) -> [FriendTimelineDay] {
        let me = ClaimIdentity.user(currentUserID)
        let calendar = Calendar.current
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "MMM d"

        struct Dated { let date: Date; let created: Date; let entry: FriendTimelineEntry }
        var all: [Dated] = []

        for trip in ctx.trips {
            guard let myPID = ctx.personID(in: trip, claim: me),
                  let friendPID = ctx.personID(in: trip, claim: friend) else { continue }
            let source = ctx.sourceName(trip)
            let peopleByID = Dictionary(trip.people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            for e in trip.expenses where e.deletedAt == nil {
                let parties = Set(e.payments.map(\.tripPersonID)).union(e.splits.map(\.tripPersonID))
                guard parties.contains(myPID) && parties.contains(friendPID) else { continue }
                let payerName: String
                let payerIsYou: Bool
                if e.payments.count > 1 {
                    payerName = "\(e.payments.count) people"; payerIsYou = false
                } else if let first = e.primaryPayerID {
                    payerIsYou = first == myPID
                    payerName = payerIsYou ? "you" : (peopleByID[first]?.displayName ?? "Member")
                } else {
                    payerName = "\u{2014}"; payerIsYou = false
                }
                let yourShare = e.splits.first { $0.tripPersonID == myPID }?.amountOwed ?? 0
                let row = ExpenseRowItem(
                    id: e.id, categoryID: e.categoryID, icon: "tag", name: e.descriptionText,
                    payerName: payerName, payerIsYou: payerIsYou,
                    yourShare: MoneyFormatter.format(yourShare, currency: e.currency),
                    totalAmount: MoneyFormatter.format(e.amount, currency: e.currency),
                    sourceName: source
                )
                all.append(Dated(date: e.expenseDate, created: e.createdAt,
                                 entry: FriendTimelineEntry(id: e.id, sourceName: source, item: .expense(row))))
            }

            for s in trip.settlements where s.deletedAt == nil {
                let pair: Set<UUID> = [s.fromPersonID, s.toPersonID]
                guard pair == [myPID, friendPID] else { continue }
                let fromName = s.fromPersonID == myPID ? "You" : (peopleByID[s.fromPersonID]?.displayName ?? "Member")
                let toName = s.toPersonID == myPID ? "you" : (peopleByID[s.toPersonID]?.displayName ?? "Member")
                let row = SettlementRowItem(
                    id: s.id, fromName: fromName, toName: toName,
                    formattedAmount: MoneyFormatter.format(s.amount, currency: s.currency),
                    text: "\(fromName) settled with \(toName)",
                    sourceName: source
                )
                all.append(Dated(date: s.settledAt, created: s.createdAt,
                                 entry: FriendTimelineEntry(id: s.id, sourceName: source, item: .settlement(row))))
            }
        }

        let grouped = Dictionary(grouping: all) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let entries = (grouped[day] ?? []).sorted { $0.created > $1.created }.map(\.entry)
            return FriendTimelineDay(
                id: ISO8601DateFormatter().string(from: day),
                dateLabel: labelFormatter.string(from: day),
                entries: entries
            )
        }
    }
}
