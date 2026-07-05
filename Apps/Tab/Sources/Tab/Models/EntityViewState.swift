import Foundation
import TabCore

// MARK: - Entity → TabCore

extension ExpenseSplitEntity {
    var splitType: SplitType { SplitType(rawValue: splitTypeRaw) ?? .equal }

    func toCoreSplit() -> ExpenseSplit {
        ExpenseSplit(
            participantID: tripPersonID,
            amountOwed: amountOwed,
            splitType: splitType,
            shareUnits: shareUnits,
            percentage: percentage
        )
    }
}

extension PaymentEntity {
    var paymentMode: PaymentMode { PaymentMode(rawValue: paymentModeRaw) ?? .equal }

    func toCorePayment() -> Payment {
        Payment(payerID: tripPersonID, amountPaid: amountPaid, paymentMode: paymentMode)
    }
}

extension ExpenseEntity {
    /// First payer by deterministic ordering. Suitable for single-payer display only.
    var primaryPayerID: UUID? {
        payments.sorted { $0.tripPersonID.uuidString < $1.tripPersonID.uuidString }.first?.tripPersonID
    }

    var paymentMethod: PaymentMethod {
        PaymentMethod(rawValue: paymentMethodRaw) ?? .card
    }

    func toCoreExpense() -> Expense {
        Expense(
            id: id,
            tripID: trip?.id ?? UUID(),
            amount: Money(amount: amount, currency: currency),
            categoryID: categoryID,
            descriptionText: descriptionText,
            receiptStoragePath: receiptStoragePath,
            paymentMethod: paymentMethod,
            expenseDate: expenseDate,
            payments: payments.map { $0.toCorePayment() },
            splits: splits.map { $0.toCoreSplit() },
            createdBy: createdByID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

extension SettlementEntity {
    func toCoreSettlement() -> Settlement {
        Settlement(
            id: id,
            tripID: trip?.id ?? UUID(),
            fromUserID: fromPersonID,
            toUserID: toPersonID,
            amount: Money(amount: amount, currency: currency),
            note: note,
            settledAt: settledAt,
            createdBy: createdByID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

// MARK: - Entity → ViewState (computed in views, MainActor)

@MainActor
enum TripPresenter {
    /// Builds the trip-list card view-state. Computes balances via TabCore.
    static func card(
        from trip: TripEntity,
        currentPersonID: UUID,
        currentUserDisplayName: String? = nil,
        now: Date = .now
    ) -> TripCard {
        let members = trip.activePeople.sortedForDisplay(currentPersonID: currentPersonID).map { person -> MemberCard in
            if person.id == currentPersonID {
                return MemberCard(id: person.id, displayName: "You", avatarName: currentUserDisplayName ?? person.displayName)
            }
            return MemberCard(id: person.id, displayName: person.displayName)
        }

        let activeExpenses = trip.expenses.filter { $0.deletedAt == nil }
        let activeSettlements = trip.settlements.filter { $0.deletedAt == nil }
        let coreExpenses = activeExpenses.map { $0.toCoreExpense() }
        let coreSettlements = activeSettlements.map { $0.toCoreSettlement() }
        let balances = BalanceEngine.compute(expenses: coreExpenses, settlements: coreSettlements)
        let state = TripStateDeriver.derive(balances: balances, lastActivityAt: trip.lastActivityAt, now: now)

        let mine = balances.filter { $0.forUser == currentPersonID }
        let netByCurrency = Dictionary(grouping: mine, by: \.currency)
            .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }
            .filter { $0.value != 0 }

        let status: TripCard.Status
        if state == .completed {
            status = .settled("settled · \(monthYear(trip.lastActivityAt))")
        } else if netByCurrency.isEmpty {
            status = activeExpenses.isEmpty && activeSettlements.isEmpty ? .empty : .settled("all settled")
        } else {
            let owed = netByCurrency.filter { $0.value > 0 }
            let owe = netByCurrency.filter { $0.value < 0 }
            if !owed.isEmpty && owe.isEmpty {
                let parts = owed
                    .sorted { $0.key < $1.key }
                    .map { MoneyFormatter.format($0.value, currency: $0.key) }
                status = .owed("you're owed " + parts.joined(separator: " + "))
            } else if !owe.isEmpty && owed.isEmpty {
                let parts = owe
                    .sorted { $0.key < $1.key }
                    .map { MoneyFormatter.format(-$0.value, currency: $0.key) }
                status = .owe("you owe " + parts.joined(separator: " + "))
            } else {
                let parts = netByCurrency
                    .sorted { $0.key < $1.key }
                    .map { (cur, amt) -> String in
                        amt > 0
                            ? "+" + MoneyFormatter.format(amt, currency: cur)
                            : "-" + MoneyFormatter.format(-amt, currency: cur)
                    }
                status = .owed("net " + parts.joined(separator: " "))
            }
        }

        return TripCard(
            id: trip.id,
            name: trip.name,
            members: members,
            status: status,
            isCompleted: state == .completed
        )
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    private static func monthYear(_ date: Date) -> String {
        monthYearFormatter.string(from: date)
    }
}

@MainActor
enum BalancePresenter {
    /// One BalanceSummary per currency with non-zero net for the current user.
    static func summaries(
        expenses: [ExpenseEntity],
        settlements: [SettlementEntity],
        people: [TripPersonEntity],
        currentPersonID: UUID,
        personFor: (UUID) -> TripPersonEntity?
    ) -> [BalanceSummary] {
        let coreExpenses = expenses.filter { $0.deletedAt == nil }.map { $0.toCoreExpense() }
        let coreSettlements = settlements.filter { $0.deletedAt == nil }.map { $0.toCoreSettlement() }
        let balances = BalanceEngine.compute(expenses: coreExpenses, settlements: coreSettlements)
        let mine = balances.filter { $0.forUser == currentPersonID }
        let byCurrency = Dictionary(grouping: mine, by: \.currency)

        return byCurrency.keys.sorted().compactMap { currency -> BalanceSummary? in
            let entries = byCurrency[currency] ?? []
            let net = entries.reduce(Decimal(0)) { $0 + $1.amount }
            if net == 0 { return nil }

            let label = net > 0 ? "You're owed" : "You owe"
            let displayAmount = MoneyFormatter.format(net > 0 ? net : -net, currency: currency)

            let details: [BalanceDetailItem] = entries
                .filter { $0.amount != 0 }
                .map { entry in
                    BalanceDetailCandidate(
                        entry: entry,
                        name: personFor(entry.withUser)?.displayName ?? "Member"
                    )
                }
                .sorted { lhs, rhs in
                    let lhsAmount = abs(lhs.entry.amount)
                    let rhsAmount = abs(rhs.entry.amount)
                    if lhsAmount != rhsAmount { return lhsAmount > rhsAmount }

                    let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    if nameOrder != .orderedSame { return nameOrder == .orderedAscending }

                    return lhs.entry.withUser.uuidString < rhs.entry.withUser.uuidString
                }
                .map { candidate in
                    let entry = candidate.entry
                    let phrase = entry.amount > 0
                        ? "\(candidate.name) owes you"
                        : "You owe \(candidate.name)"
                    let amount = MoneyFormatter.format(
                        entry.amount > 0 ? entry.amount : -entry.amount,
                        currency: currency
                    )
                    return BalanceDetailItem(id: entry.withUser, counterparty: phrase, amount: amount)
                }

            return BalanceSummary(label: label, amount: displayAmount, details: details)
        }
    }

    private struct BalanceDetailCandidate {
        let entry: UserBalance
        let name: String
    }
}

enum SettleUpPresenter {
    /// Prefer debts the current person can pay off before suggesting that
    /// someone else reimburse them. This matches the form's "From pays To"
    /// direction and avoids defaulting to a payment that increases a debt.
    static func suggestedPayment(
        balances: [UserBalance],
        currentPersonID: UUID
    ) -> SettleUpSuggestion? {
        if let balance = balances
            .filter({ $0.forUser == currentPersonID && $0.amount < 0 })
            .max(by: { abs($0.amount) < abs($1.amount) }) {
            return SettleUpSuggestion(
                fromPersonID: currentPersonID,
                toPersonID: balance.withUser,
                amount: -balance.amount,
                currency: balance.currency
            )
        }

        guard let balance = balances
            .filter({ $0.forUser == currentPersonID && $0.amount > 0 })
            .max(by: { $0.amount < $1.amount })
        else { return nil }

        return SettleUpSuggestion(
            fromPersonID: balance.withUser,
            toPersonID: currentPersonID,
            amount: balance.amount,
            currency: balance.currency
        )
    }
}

@MainActor
enum TimelinePresenter {
    private static let dayIDFormatter = ISO8601DateFormatter()

    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static func days(
        expenses: [ExpenseEntity],
        settlements: [SettlementEntity],
        currentPersonID: UUID,
        personFor: (UUID) -> TripPersonEntity?,
        categoryFor: (UUID?) -> CategoryEntity?
    ) -> [TimelineDay] {
        let calendar = Calendar.current

        let activeExpenses = expenses.filter { $0.deletedAt == nil }
        let activeSettlements = settlements.filter { $0.deletedAt == nil }

        struct Dated: Identifiable {
            let id: UUID
            let date: Date
            let created: Date
            let item: TimelineItem
        }

        var all: [Dated] = []

        for e in activeExpenses {
            let category = categoryFor(e.categoryID)
            let payerName: String
            let payerIsYou: Bool
            if e.payments.count > 1 {
                payerName = "\(e.payments.count) people"
                payerIsYou = false
            } else if let firstPayer = e.primaryPayerID {
                payerIsYou = firstPayer == currentPersonID
                payerName = payerIsYou
                    ? "you"
                    : (personFor(firstPayer)?.displayName ?? "Member")
            } else {
                payerName = "\u{2014}"
                payerIsYou = false
            }
            let yourShare = e.splits
                .first(where: { $0.tripPersonID == currentPersonID })?.amountOwed ?? 0
            let rowItem = ExpenseRowItem(
                id: e.id,
                categoryID: category?.id ?? e.categoryID,
                icon: category?.icon ?? "tag",
                name: e.descriptionText,
                payerName: payerName,
                payerIsYou: payerIsYou,
                yourShare: MoneyFormatter.format(yourShare, currency: e.currency),
                totalAmount: MoneyFormatter.format(e.amount, currency: e.currency)
            )
            all.append(Dated(id: e.id, date: e.expenseDate, created: e.createdAt, item: .expense(rowItem)))
        }

        for s in activeSettlements {
            let fromName = s.fromPersonID == currentPersonID
                ? "You"
                : (personFor(s.fromPersonID)?.displayName ?? "Member")
            let toName = s.toPersonID == currentPersonID
                ? "you"
                : (personFor(s.toPersonID)?.displayName ?? "Member")
            let text = "\(fromName) settled with \(toName)"
            let rowItem = SettlementRowItem(
                id: s.id,
                fromName: fromName,
                toName: toName,
                formattedAmount: MoneyFormatter.format(s.amount, currency: s.currency),
                text: text
            )
            all.append(Dated(id: s.id, date: s.settledAt, created: s.createdAt, item: .settlement(rowItem)))
        }

        let grouped = Dictionary(grouping: all) { calendar.startOfDay(for: $0.date) }

        return grouped.keys.sorted(by: >).map { day -> TimelineDay in
            let dayItems = (grouped[day] ?? [])
                .sorted { $0.created > $1.created }
                .map(\.item)
            return TimelineDay(
                id: dayIDFormatter.string(from: day),
                dateLabel: dayLabelFormatter.string(from: day),
                items: dayItems
            )
        }
    }
}

extension CategoryEntity {
    var asOption: CategoryOption {
        CategoryOption(id: id, icon: icon, name: name)
    }
}

extension Sequence where Element == TripPersonEntity {
    func sortedForDisplay(currentPersonID: UUID?) -> [TripPersonEntity] {
        sorted { lhs, rhs in
            if lhs.id == currentPersonID { return true }
            if rhs.id == currentPersonID { return false }
            if (lhs.joinedAt != nil) != (rhs.joinedAt != nil) {
                return lhs.joinedAt != nil
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
