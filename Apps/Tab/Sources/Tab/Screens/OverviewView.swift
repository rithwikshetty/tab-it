import SwiftUI
import Charts

/// Per-trip spend [[Overview]] — Direction A (donut-led).
/// Summary (total / you paid / your share) → per-person → by-category.
/// Scoped to one currency; a picker appears only when the trip has more than one.
struct OverviewView: View {
    let state: OverviewState
    @State private var currencyIndex: Int = 0

    private var page: OverviewPage? {
        guard !state.pages.isEmpty else { return nil }
        return state.pages[min(currencyIndex, state.pages.count - 1)]
    }

    var body: some View {
        if let page {
            VStack(spacing: 0) {
                if state.currencies.count > 1 {
                    currencyPicker
                }
                summaryCard(page)
                if !page.people.isEmpty {
                    peopleCard(page)
                }
                if !page.categories.isEmpty {
                    categoryCard(page)
                }
            }
        } else {
            emptyState
        }
    }

    // MARK: currency picker

    private var currencyPicker: some View {
        HStack {
            Spacer()
            Menu {
                ForEach(Array(state.currencies.enumerated()), id: \.offset) { index, code in
                    Button {
                        currencyIndex = index
                    } label: {
                        if index == currencyIndex {
                            Label(code, systemImage: "checkmark")
                        } else {
                            Text(code)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(state.currencies[min(currencyIndex, state.currencies.count - 1)])
                        .font(.system(size: 12, weight: .semibold))
                        .monospaced()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Sage.accentStrong)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Sage.accentTint, in: Capsule())
                .overlay(Capsule().stroke(Sage.accentSoft, lineWidth: 1))
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    // MARK: summary

    private func summaryCard(_ page: OverviewPage) -> some View {
        Card {
            // Donut beside the stats when the amounts are short; donut stacked
            // above them when the amounts run long (e.g. large JPY totals), so a
            // big number never crushes the chart. ViewThatFits picks whatever fits,
            // and only falls back to shrinking text inside a layout as a last resort.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) {
                    donut(page)
                    summaryStats(page)
                    Spacer(minLength: 0)
                }
                .padding(18)

                VStack(alignment: .leading, spacing: 18) {
                    donut(page).frame(maxWidth: .infinity, alignment: .center)
                    summaryStats(page).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
            }
        }
    }

    private func donut(_ page: OverviewPage) -> some View {
        let shareFraction = page.people.first(where: \.isYou)?.shareFraction ?? 0
        return ZStack {
            Chart {
                SectorMark(angle: .value("Your share", shareFraction), innerRadius: .ratio(0.70), angularInset: 1.2)
                    .foregroundStyle(Sage.accentStrong)
                SectorMark(angle: .value("Rest", max(0.0001, 1 - shareFraction)), innerRadius: .ratio(0.70), angularInset: 1.2)
                    .foregroundStyle(Sage.accentSoft)
            }
            .frame(width: 116, height: 116)
            // Total lives inside the hole. Width is clamped well inside the inner
            // radius and the amount scales down (not out), so a large total — e.g.
            // £48,000.00 — shrinks to fit rather than bleeding into the ring.
            VStack(spacing: 2) {
                Text("TOTAL").font(.system(size: 8.5, weight: .semibold)).tracking(0.8).foregroundStyle(Sage.textSecondary)
                Text(page.totalSpent).font(.system(size: 13, weight: .semibold)).monospaced().foregroundStyle(Sage.text)
                    .lineLimit(1).minimumScaleFactor(0.4)
            }
            .frame(width: 70)
        }
        .frame(width: 116, height: 116)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Total spend \(page.totalSpent)"
                + (page.yourSharePercent.map { ", your share is \($0)" } ?? "")
        )
    }

    private func summaryStats(_ page: OverviewPage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            statLine("You paid", page.youPaid, color: Sage.text)
            statLine("Your share", page.yourShare, color: Sage.accentStrong)
        }
    }

    private func statLine(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Sage.textSecondary)
            Text(value).font(.system(size: 19, weight: .semibold)).monospaced().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.55)
        }
    }

    // MARK: people

    private func peopleCard(_ page: OverviewPage) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                cardEyebrow("Per person · paid vs share")
                    .padding(.bottom, 6)
                ForEach(Array(page.people.enumerated()), id: \.element.id) { index, person in
                    if index > 0 { RowDivider() }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(person.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Sage.text)
                            GeometryReader { geo in
                                Capsule().fill(Sage.surface2)
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Sage.accent)
                                            .frame(width: max(2, geo.size.width * person.shareFraction))
                                    }
                            }
                            .frame(height: 6)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(person.share).font(.system(size: 13, weight: .semibold)).monospaced().foregroundStyle(Sage.text)
                            Text("paid \(person.paid)").font(.system(size: 10.5)).monospaced().foregroundStyle(Sage.textSecondary)
                        }
                    }
                    .padding(.vertical, 11)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 6)
        }
    }

    // MARK: category

    private func categoryCard(_ page: OverviewPage) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                cardEyebrow("By category").padding(.bottom, -2)
                ForEach(page.categories) { cat in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(color(for: cat.categoryID)).frame(width: 9, height: 9)
                            Text(cat.name).font(.system(size: 13)).foregroundStyle(Sage.text)
                            Spacer()
                            Text(cat.amount).font(.system(size: 12.5, weight: .semibold)).monospaced().foregroundStyle(Sage.text)
                        }
                        GeometryReader { geo in
                            Capsule().fill(Sage.surface2)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(color(for: cat.categoryID))
                                        .frame(width: max(3, geo.size.width * cat.fraction))
                                }
                        }
                        .frame(height: 8)
                    }
                }
            }
            .padding(18)
        }
    }

    // MARK: helpers

    private func cardEyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(1.0)
            .foregroundStyle(Sage.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for categoryID: UUID?) -> Color {
        guard let categoryID else { return Sage.textSecondary }
        return DefaultCategories.tone(for: categoryID)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 16).fill(Sage.accentTint)
                .frame(width: 54, height: 54)
                .overlay(Image(systemName: "chart.bar.xaxis").font(.system(size: 22)).foregroundStyle(Sage.accent))
                .padding(.bottom, 8)
            Text("Nothing to break down yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(Sage.text)
            Text("Spending charts appear here once\nthe trip has its first expense.")
                .font(.system(size: 13)).foregroundStyle(Sage.textSecondary).multilineTextAlignment(.center)
        }
        .padding(.top, 50)
        .frame(maxWidth: .infinity)
    }
}
