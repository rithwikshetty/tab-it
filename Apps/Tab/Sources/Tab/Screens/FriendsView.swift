import SwiftUI
import SwiftData
import TabCore

struct FriendsView: View {
    var onOpenFriend: (FriendIdentity) -> Void = { _ in }
    var onAddExpense: () -> Void = {}

    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    // Both trips and non-group containers; the presenter nets across all of them.
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil })
    private var trips: [TripEntity]

    private var state: FriendsListState? {
        guard let uid = auth.currentUser?.id else { return nil }
        return FriendsPresenter.list(trips: trips, currentUserID: uid)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LargeTitle(title: "Friends")

                if let state, !state.isEmpty {
                    if !state.overall.isEmpty {
                        OverallBanner(lines: state.overall)
                    }
                    if !state.active.isEmpty {
                        SectionHeaderText(title: "People")
                        Card { rows(state.active) }
                    }
                    if !state.settled.isEmpty {
                        SectionHeaderText(title: "Settled up")
                        Card { rows(state.settled) }
                    }
                } else {
                    EmptyFriendsView()
                }

                Spacer(minLength: FloatingActionLayout.scrollBottomClearance)
            }
            .scrollIndicators(.hidden)
            .background(Sage.bg.ignoresSafeArea())
            .refreshable { await sync.pullAll() }

            Fab(label: "Add expense", systemImage: "plus", accessibilityIdentifier: "friends.addButton") {
                onAddExpense()
            }
            .floatingActionPlacement()
        }
    }

    @ViewBuilder
    private func rows(_ friends: [FriendRow]) -> some View {
        ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
            Button { onOpenFriend(friend.friend) } label: {
                FriendRowView(friend: friend)
            }
            .buttonStyle(.plain)
            if index < friends.count - 1 { RowDivider() }
        }
    }
}

private struct FriendRowView: View {
    let friend: FriendRow

    var body: some View {
        HStack(spacing: 13) {
            Avatar(initial: friend.initial, tone: friend.tone, size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text(friend.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Sage.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(friend.isPending ? "Invite pending" : friend.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Sage.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if friend.isSettled {
                Text("all settled")
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.textSecondary)
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    ForEach(friend.lines) { line in
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(line.label)
                                .font(.system(size: 10, weight: .semibold))
                                .textCase(.uppercase)
                                .tracking(0.4)
                                .foregroundStyle(Sage.textSecondary)
                            Text(line.amount)
                                .font(.system(size: 16, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(line.isPositive ? Sage.accentStrong : Sage.warning)
                        }
                    }
                }
            }
            Chevron(size: 12)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 15)
        .contentShape(Rectangle())
    }
}

private struct OverallBanner: View {
    let lines: [FriendsOverallLine]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 5) {
                Text("Overall")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(Sage.textSecondary)
                ForEach(lines) { line in
                    bannerLine(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func bannerLine(_ line: FriendsOverallLine) -> some View {
        // One wrapping Text (not an HStack of Texts) so long multi-currency amounts
        // wrap to the next line instead of clipping off the edge of the card.
        var text = Text("")
        if line.youOwe > 0 {
            text = text + phrase("You owe ", MoneyFormatter.format(line.youOwe, currency: line.currency), Sage.warning)
        }
        if line.youOwe > 0 && line.youAreOwed > 0 {
            text = text + Text("  ·  ").foregroundStyle(Sage.textSecondary)
        }
        if line.youAreOwed > 0 {
            text = text + phrase("you are owed ", MoneyFormatter.format(line.youAreOwed, currency: line.currency), Sage.accentStrong)
        }
        return text
            .font(.system(size: 14))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func phrase(_ label: String, _ amount: String, _ color: Color) -> Text {
        Text(label).foregroundStyle(Sage.textSecondary)
            + Text(amount).foregroundStyle(color).fontWeight(.bold)
    }
}

private struct EmptyFriendsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Sage.textSecondary)
            Text("No friends yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Sage.text)
            Text("Add an expense or start a trip to see who you owe")
                .font(.system(size: 14))
                .foregroundStyle(Sage.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 80)
        .padding(.bottom, 40)
    }
}
