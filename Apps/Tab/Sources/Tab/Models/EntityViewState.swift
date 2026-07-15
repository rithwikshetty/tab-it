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
        let simplifiedBalances = DebtSimplifier.simplify(balances).flatMap { debt in
            [
                UserBalance(forUser: debt.toUser, withUser: debt.fromUser, currency: debt.currency, amount: debt.amount),
                UserBalance(forUser: debt.fromUser, withUser: debt.toUser, currency: debt.currency, amount: -debt.amount),
            ]
        }
        let state = TripStateDeriver.derive(
            balances: simplifiedBalances,
            lastActivityAt: trip.lastActivityAt,
            now: now
        )

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
                status = .mixed("net " + parts.joined(separator: " "))
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
    /// Detail rows are the current user's simplified debts, so the card always
    /// matches the trip-wide simplified repayments rather than raw pairwise
    /// balances. Simplification preserves net positions, so the headline
    /// amount is unchanged by this.
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
        let mine = DebtSimplifier.simplify(balances)
            .filter { $0.fromUser == currentPersonID || $0.toUser == currentPersonID }
        let byCurrency = Dictionary(grouping: mine, by: \.currency)

        return byCurrency.keys.sorted().compactMap { currency -> BalanceSummary? in
            let debts = byCurrency[currency] ?? []
            let net = debts.reduce(Decimal(0)) { sum, debt in
                debt.toUser == currentPersonID ? sum + debt.amount : sum - debt.amount
            }
            if net == 0 { return nil }

            let label = net > 0 ? "You're owed" : "You owe"
            let displayAmount = MoneyFormatter.format(net > 0 ? net : -net, currency: currency)

            let details: [BalanceDetailItem] = debts
                .map { debt -> BalanceDetailCandidate in
                    let otherID = debt.toUser == currentPersonID ? debt.fromUser : debt.toUser
                    return BalanceDetailCandidate(
                        debt: debt,
                        otherID: otherID,
                        name: personFor(otherID)?.displayName ?? "Member"
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.debt.amount != rhs.debt.amount { return lhs.debt.amount > rhs.debt.amount }

                    let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    if nameOrder != .orderedSame { return nameOrder == .orderedAscending }

                    return lhs.otherID.uuidString < rhs.otherID.uuidString
                }
                .map { candidate in
                    let lent = candidate.debt.toUser == currentPersonID
                    return BalanceDetailItem(
                        id: candidate.otherID,
                        counterparty: lent
                            ? "\(candidate.name) owes you"
                            : "You owe \(candidate.name)",
                        amount: MoneyFormatter.format(candidate.debt.amount, currency: currency),
                        semantic: lent ? .lent : .borrowed
                    )
                }

            return BalanceSummary(
                label: label,
                amount: displayAmount,
                details: details,
                semantic: net > 0 ? .lent : .borrowed
            )
        }
    }

    /// The same trip-wide simplified debts for every joined member, grouped by currency.
    static func simplifiedGroups(
        expenses: [ExpenseEntity],
        settlements: [SettlementEntity],
        currentPersonID: UUID,
        personFor: (UUID) -> TripPersonEntity?
    ) -> [SimplifiedDebtGroup] {
        let coreExpenses = expenses.filter { $0.deletedAt == nil }.map { $0.toCoreExpense() }
        let coreSettlements = settlements.filter { $0.deletedAt == nil }.map { $0.toCoreSettlement() }
        let balances = BalanceEngine.compute(expenses: coreExpenses, settlements: coreSettlements)
        let byCurrency = Dictionary(grouping: DebtSimplifier.simplify(balances), by: \.currency)

        return byCurrency.keys.sorted().map { currency in
            let rows = (byCurrency[currency] ?? []).map { debt in
                let fromName = debt.fromUser == currentPersonID
                    ? "You"
                    : (personFor(debt.fromUser)?.displayName ?? "Member")
                let toName = debt.toUser == currentPersonID
                    ? "you"
                    : (personFor(debt.toUser)?.displayName ?? "Member")
                let semantic: BalanceSemantic = if debt.toUser == currentPersonID {
                    .lent
                } else if debt.fromUser == currentPersonID {
                    .borrowed
                } else {
                    .neutral
                }
                return SimplifiedDebtRowItem(
                    id: "\(currency)-\(debt.fromUser.uuidString)-\(debt.toUser.uuidString)",
                    fromName: fromName,
                    toName: toName,
                    amount: MoneyFormatter.format(debt.amount, currency: currency),
                    semantic: semantic,
                    suggestion: SettleUpSuggestion(
                        fromPersonID: debt.fromUser,
                        toPersonID: debt.toUser,
                        amount: debt.amount,
                        currency: currency
                    )
                )
            }
            return SimplifiedDebtGroup(currency: currency, debts: rows)
        }
    }

    private struct BalanceDetailCandidate {
        let debt: SimplifiedDebt
        let otherID: UUID
        let name: String
    }
}

enum SettleUpPresenter {
    /// Prefer paying off the current person's own simplified debt before
    /// suggesting that someone else reimburse them.
    static func suggestedPayment(
        balances: [UserBalance],
        currentPersonID: UUID
    ) -> SettleUpSuggestion? {
        let debts = DebtSimplifier.simplify(balances)

        if let debt = debts
            .filter({ $0.fromUser == currentPersonID })
            .sorted(by: { paymentPrecedes($0, $1, counterparty: \SimplifiedDebt.toUser) })
            .first {
            return SettleUpSuggestion(
                fromPersonID: currentPersonID,
                toPersonID: debt.toUser,
                amount: debt.amount,
                currency: debt.currency
            )
        }

        guard let debt = debts
            .filter({ $0.toUser == currentPersonID })
            .sorted(by: { paymentPrecedes($0, $1, counterparty: \SimplifiedDebt.fromUser) })
            .first else { return nil }

        return SettleUpSuggestion(
            fromPersonID: debt.fromUser,
            toPersonID: currentPersonID,
            amount: debt.amount,
            currency: debt.currency
        )
    }

    private static func paymentPrecedes(
        _ lhs: SimplifiedDebt,
        _ rhs: SimplifiedDebt,
        counterparty: KeyPath<SimplifiedDebt, UUID>
    ) -> Bool {
        if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
        if lhs.currency != rhs.currency { return lhs.currency < rhs.currency }
        return lhs[keyPath: counterparty].uuidString < rhs[keyPath: counterparty].uuidString
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

        struct DayAmounts {
            var totalSpend: Decimal = 0
            var yourShare: Decimal = 0
        }

        var all: [Dated] = []
        var totalsByDay: [Date: [String: DayAmounts]] = [:]

        for e in activeExpenses {
            let category = categoryFor(e.categoryID)
            let payerName: String
            if e.payments.count > 1 {
                payerName = "\(e.payments.count) people"
            } else if let firstPayer = e.primaryPayerID {
                payerName = firstPayer == currentPersonID
                    ? "you"
                    : (personFor(firstPayer)?.displayName ?? "Member")
            } else {
                payerName = "\u{2014}"
            }
            let yourShare = e.splits
                .filter { $0.tripPersonID == currentPersonID }
                .reduce(Decimal(0)) { $0 + $1.amountOwed }
            let yourPayment = e.payments
                .filter { $0.tripPersonID == currentPersonID }
                .reduce(Decimal(0)) { $0 + $1.amountPaid }
            let net = yourPayment - yourShare
            let balanceSemantic: BalanceSemantic = if net > 0 {
                .lent
            } else if net < 0 {
                .borrowed
            } else {
                .neutral
            }
            let balanceLabel: String? = if net > 0 {
                "you lent \(MoneyFormatter.format(net, currency: e.currency))"
            } else if net < 0 {
                "you borrowed \(MoneyFormatter.format(-net, currency: e.currency))"
            } else {
                nil
            }
            let rowItem = ExpenseRowItem(
                id: e.id,
                categoryID: category?.id ?? e.categoryID,
                icon: category?.icon ?? "tag",
                name: e.descriptionText,
                payerName: payerName,
                yourShare: MoneyFormatter.format(yourShare, currency: e.currency),
                balanceLabel: balanceLabel,
                balanceSemantic: balanceSemantic
            )
            all.append(Dated(id: e.id, date: e.expenseDate, created: e.createdAt, item: .expense(rowItem)))

            let day = calendar.startOfDay(for: e.expenseDate)
            var currencyTotals = totalsByDay[day] ?? [:]
            var amounts = currencyTotals[e.currency] ?? DayAmounts()
            amounts.totalSpend += e.amount
            amounts.yourShare += yourShare
            currencyTotals[e.currency] = amounts
            totalsByDay[day] = currencyTotals
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
            let totals = (totalsByDay[day] ?? [:]).keys.sorted().map { currency in
                let amounts = totalsByDay[day]?[currency] ?? DayAmounts()
                return TimelineDayTotal(
                    currency: currency,
                    totalSpend: MoneyFormatter.format(amounts.totalSpend, currency: currency),
                    yourShare: MoneyFormatter.format(amounts.yourShare, currency: currency)
                )
            }
            return TimelineDay(
                id: dayIDFormatter.string(from: day),
                dateLabel: dayLabelFormatter.string(from: day),
                totals: totals,
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
