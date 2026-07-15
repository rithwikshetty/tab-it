import SwiftUI
import SwiftData

struct ActivityView: View {
    var onOpen: (ActivityTarget) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query(sort: \ActivityEntity.timestamp, order: .reverse) private var activities: [ActivityEntity]
    @Query private var profiles: [ProfileEntity]
    @Query private var people: [TripPersonEntity]
    @Query private var mutes: [TripMuteEntity]

    private var currentUserID: UUID? { auth.currentUser?.id }

    private var lastSeenAt: Date? {
        guard let uid = currentUserID else { return nil }
        return profiles.first { $0.id == uid }?.activityLastSeenAt
    }

    private var mutedTripIDs: Set<UUID> {
        Set(mutes.filter(\.isMuted).map(\.tripID))
    }

    private var myTripPersonIDs: Set<UUID> {
        guard let uid = currentUserID else { return [] }
        return Set(people.filter { $0.userID == uid }.map(\.id))
    }

    private var joinedAtByTrip: [UUID: Date] {
        guard let uid = currentUserID else { return [:] }
        var map: [UUID: Date] = [:]
        for person in people where person.userID == uid {
            if let tripID = person.trip?.id, let joinedAt = person.joinedAt {
                map[tripID] = joinedAt
            }
        }
        return map
    }

    private var sections: [ActivitySection] {
        guard let uid = currentUserID else { return [] }
        return ActivityPresenter.sections(
            from: activities,
            currentUserID: uid,
            lastSeenAt: lastSeenAt,
            mutedTripIDs: mutedTripIDs,
            myTripPersonIDs: myTripPersonIDs,
            joinedAtByTrip: joinedAtByTrip
        )
    }

    var body: some View {
        // Hoisted so the feed presenter runs once per render, not once per access.
        let sections = self.sections

        List {
            Section {
                LargeTitle(title: "Activity")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if sections.isEmpty {
                Section {
                    EmptyActivityView()
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(sections) { section in
                    Section {
                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                            Button {
                                Haptics.light()
                                markRead(rowID: row.id)
                                onOpen(row.target)
                            } label: {
                                ActivityRowView(row: row)
                            }
                            .buttonStyle(.plain)
                            // Unread is otherwise only visual (tint + dot);
                            // surface it for VoiceOver (and UI tests).
                            .accessibilityValue(row.isUnread ? "Unread" : "Read")
                            .listRowInsets(EdgeInsets())
                            // Unread is a background tint + dot, never a font
                            // change: text metrics stay identical across the
                            // read flip so marking read can't rewrap the title.
                            .listRowBackground(row.isUnread ? Sage.accentTint : Sage.surface)
                            // Top edge always hidden: it renders as a stray
                            // line between the date header and the card.
                            .listRowSeparator(.hidden, edges: .top)
                            .listRowSeparator(index == section.rows.count - 1 ? .hidden : .visible, edges: .bottom)
                            .listRowSeparatorTint(Sage.rowDivider)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if row.isUnread {
                                    Button("Mark as read") {
                                        markRead(rowID: row.id)
                                    }
                                    .tint(Sage.accent)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Delete", role: .destructive) {
                                    dismissRow(rowID: row.id)
                                }
                            }
                        }
                    } header: {
                    Text(section.dateLabel.uppercased())
                        .font(.dateHeader)
                        .tracking(1.32)
                        .foregroundStyle(Sage.textSecondary)
                        .padding(.leading, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Section {
                Color.clear
                    .frame(height: 96)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(Sage.bg.ignoresSafeArea())
        .refreshable { await sync.pullAll() }
        .task(id: currentUserID) {
            await sync.pullAll()
        }
        .onDisappear {
            // Leaving the tab (or pushing a detail) marks everything read:
            // unread is a "new since you last looked" signal, not an inbox
            // the user has to clear by hand.
            guard activities.contains(where: { $0.readAt == nil }) else { return }
            Task { await sync.markActivitySeen() }
        }
    }

    private func markRead(rowID: UUID) {
        guard let activity = activities.first(where: { $0.id == rowID }) else { return }
        guard activity.readAt == nil else { return }
        withAnimation {
            activity.readAt = .now
            try? context.save()
        }
    }

    private func dismissRow(rowID: UUID) {
        guard let activity = activities.first(where: { $0.id == rowID }) else { return }
        let now = Date.now
        withAnimation {
            activity.dismissedAt = now
            if activity.readAt == nil { activity.readAt = now }
            try? context.save()
        }
    }
}

private struct ActivityRowView: View {
    let row: ActivityRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill((row.isNegative ? Sage.warning : Sage.accent).opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: row.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(row.isNegative ? Sage.warning : Sage.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Sage.text)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(row.tripName)
                    if let detail = row.detail {
                        Text("·")
                        Text(detail)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Sage.textSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let trailing = row.trailing {
                    Text(trailing)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Sage.text)
                        .monospacedDigit()
                }
                Text(row.timeText)
                    .font(.system(size: 11))
                    .foregroundStyle(Sage.textSecondary)
            }

            // Constant-width slot: the dot fading (rather than leaving the
            // layout) keeps the title's wrap width identical across the
            // read/unread flip, so marking read doesn't rewrap the text.
            Circle()
                .fill(Sage.accent)
                .frame(width: 8, height: 8)
                .opacity(row.isUnread ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct EmptyActivityView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Sage.textSecondary)
            Text("No activity yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Sage.text)
            Text("Updates from your trips show up here")
                .font(.system(size: 14))
                .foregroundStyle(Sage.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 24)
    }
}
