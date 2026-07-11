import Foundation
import TabCore

/// Builds the per-trip spend [[Overview]] view-state from a trip's expenses.
///
/// The entity entry point (`overview`) is thin glue over `ExpenseEntity.toCoreExpense()` and
/// `TripAnalytics`. The resolution logic (`resolve`) operates purely on `TabCore` value types plus
/// lookup closures, so it is unit-testable without SwiftData.
@MainActor
enum OverviewPresenter {
    static func overview(
        expenses: [ExpenseEntity],
        currentPersonID: UUID,
        personName: @escaping (UUID) -> String,
        categoryName: @escaping (UUID?) -> String
    ) -> OverviewState {
        let coreExpenses = expenses.filter { $0.deletedAt == nil }.map { $0.toCoreExpense() }
        let summaries = TripAnalytics.summarize(expenses: coreExpenses)
        return resolve(
            summaries: summaries,
            currentPersonID: currentPersonID,
            personName: personName,
            categoryName: categoryName
        )
    }

    /// Pure resolution: TabCore summaries + name lookups → formatted, ratio'd view-state.
    static func resolve(
        summaries: [TripSpendSummary],
        currentPersonID: UUID,
        personName: (UUID) -> String,
        categoryName: (UUID?) -> String
    ) -> OverviewState {
        let pages = summaries.map { summary -> OverviewPage in
            let total = summary.total

            let people = summary.perPerson.map { p -> OverviewPersonRow in
                let isYou = p.personID == currentPersonID
                return OverviewPersonRow(
                    id: p.personID,
                    name: isYou ? "You" : personName(p.personID),
                    isYou: isYou,
                    paid: MoneyFormatter.formatSymbol(p.paid, currency: summary.currency),
                    share: MoneyFormatter.formatSymbol(p.share, currency: summary.currency),
                    shareFraction: ratio(p.share, of: total)
                )
            }

            let maxCategory = summary.perCategory.map(\.total).max() ?? 0
            let categories = summary.perCategory.map { c -> OverviewCategoryRow in
                OverviewCategoryRow(
                    id: c.categoryID?.uuidString ?? "uncategorized",
                    categoryID: c.categoryID,
                    name: categoryName(c.categoryID),
                    amount: MoneyFormatter.formatSymbol(c.total, currency: summary.currency),
                    percent: ratio(c.total, of: total),
                    fraction: ratio(c.total, of: maxCategory)
                )
            }

            let yours = summary.perPerson.first { $0.personID == currentPersonID }
            let yourShare = yours?.share ?? 0
            let yourPaid = yours?.paid ?? 0
            let percentLabel: String? = total > 0
                ? "\(Int((ratio(yourShare, of: total) * 100).rounded()))% of trip spend"
                : nil

            return OverviewPage(
                currency: summary.currency,
                totalSpent: MoneyFormatter.formatSymbol(total, currency: summary.currency),
                youPaid: MoneyFormatter.formatSymbol(yourPaid, currency: summary.currency),
                yourShare: MoneyFormatter.formatSymbol(yourShare, currency: summary.currency),
                yourSharePercent: percentLabel,
                people: people,
                categories: categories
            )
        }
        return OverviewState(currencies: pages.map(\.currency), pages: pages)
    }

    private static func ratio(_ part: Decimal, of whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return ((part / whole) as NSDecimalNumber).doubleValue
    }
}
