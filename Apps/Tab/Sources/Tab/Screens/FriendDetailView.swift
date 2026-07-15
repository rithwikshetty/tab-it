import SwiftUI
import SwiftData
import TabCore

struct FriendDetailView: View {
    let friend: FriendIdentity
    var onSettleSource: (UUID, SettleUpSuggestion) -> Void = { _, _ in }
    var onOpenExpense: (UUID) -> Void = { _ in }
    var onOpenSettlement: (UUID) -> Void = { _ in }

    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil })
    private var trips: [TripEntity]

    private var detail: FriendDetailState? {
        guard let uid = auth.currentUser?.id else { return nil }
        return FriendsPresenter.detail(trips: trips, currentUserID: uid, friend: friend)
    }

    var body: some View {
        ScrollView {
            if let detail {
                hero(detail)

                if detail.sources.isEmpty {
                    settledNote
                } else {
                    SectionHeaderText(title: "Balance by source")
                    Card { sourceRows(detail.sources) }
                    Text("Tap a source to settle up there.")
                        .font(.system(size: 12))
                        .foregroundStyle(Sage.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 26)
                        .padding(.top, 6)
                }

                if !detail.timeline.isEmpty {
                    SectionHeaderText(title: "Shared history")
                    timeline(detail.timeline)
                }
            } else {
                Text("Nothing shared yet.")
                    .font(.system(size: 15))
                    .foregroundStyle(Sage.textSecondary)
                    .padding(.top, 80)
            }

            Spacer(minLength: 40)
        }
        .scrollIndicators(.hidden)
        .background(Sage.bg.ignoresSafeArea())
        .navigationTitle(detail?.displayName ?? "Friend")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await sync.pullAll() }
    }

    // MARK: - Hero

    @ViewBuilder
    private func hero(_ detail: FriendDetailState) -> some View {
        VStack(spacing: 10) {
            Avatar(initial: detail.initial, tone: detail.tone, size: 76, borderWidth: 0)
            Text(detail.displayName)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Sage.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 24)
            if detail.isPending {
                Text("Invite pending")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Sage.textSecondary)
            }
            if detail.overall.isEmpty {
                Text("All settled up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Sage.textSecondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(detail.overall) { line in
                        Text(netPhrase(line, name: detail.displayName))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(line.isPositive ? Sage.accentStrong : Sage.warning)
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [Sage.accentTint, Sage.bg],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private func netPhrase(_ line: FriendAmountLine, name: String) -> String {
        line.isPositive ? "\(name) owes you \(line.amount)" : "You owe \(name) \(line.amount)"
    }

    private var settledNote: some View {
        Text("You're all settled up.")
            .font(.system(size: 14))
            .foregroundStyle(Sage.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }

    // MARK: - Sources

    @ViewBuilder
    private func sourceRows(_ sources: [FriendSourceRow]) -> some View {
        ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
            Button { onSettleSource(source.containerID, source.suggestion) } label: {
                HStack(spacing: 12) {
                    Image(systemName: source.isNonGroup ? "person.2.fill" : "suitcase.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Sage.accent)
                        .frame(width: 30, height: 30)
                        .background(Sage.iconBg, in: RoundedRectangle(cornerRadius: 9))
                    Text(source.sourceName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Sage.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(source.label)
                            .font(.system(size: 10, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .foregroundStyle(Sage.textSecondary)
                        Text(source.amount)
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(source.isPositive ? Sage.accentStrong : Sage.warning)
                    }
                    Chevron(size: 12)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if index < sources.count - 1 { RowDivider() }
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private func timeline(_ days: [FriendTimelineDay]) -> some View {
        ForEach(days) { day in
            Text(day.dateLabel)
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(Sage.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 4)
            Card {
                ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                    Button { open(entry.item) } label: {
                        switch entry.item {
                        case .expense(let row): ExpenseRow(item: row)
                        case .settlement(let row): SettlementRow(item: row)
                        }
                    }
                    .buttonStyle(.plain)
                    if index < day.entries.count - 1 { RowDivider() }
                }
            }
        }
    }

    private func open(_ item: TimelineItem) {
        switch item {
        case .expense(let row): onOpenExpense(row.id)
        case .settlement(let row): onOpenSettlement(row.id)
        }
    }
}
