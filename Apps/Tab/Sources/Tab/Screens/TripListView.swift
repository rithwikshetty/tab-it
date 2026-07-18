import SwiftUI
import SwiftData

struct TripListView: View {
    var onSelect: (UUID) -> Void = { _ in }
    var onAddExpense: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query(
        filter: #Predicate<TripEntity> { $0.deletedAt == nil && $0.kind == "trip" },
        sort: \TripEntity.lastActivityAt,
        order: .reverse
    )
    private var trips: [TripEntity]

    @State private var showingNewTrip = false
    @State private var pendingDeletion: TripEntity?

    private var cards: [TripCard] {
        guard let userID = auth.currentUser?.id else { return [] }
        return trips.compactMap { trip in
            guard let currentPerson = trip.people.first(where: { $0.userID == userID }) else { return nil }
            return TripPresenter.card(
                from: trip,
                currentPersonID: currentPerson.id,
                currentUserDisplayName: auth.currentUser?.displayName
            )
        }
    }

    private var tripsByID: [UUID: TripEntity] {
        Dictionary(uniqueKeysWithValues: trips.map { ($0.id, $0) })
    }

    var body: some View {
        // Hoisted so the per-trip balance computation in `cards` runs once per
        // render instead of once per section access.
        let cards = self.cards
        let activeCards = cards.filter { !$0.isCompleted }
        let completedCards = cards.filter { $0.isCompleted }

        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                header

                if trips.isEmpty {
                    EmptyTripsView()
                } else {
                    if !activeCards.isEmpty {
                        SectionHeaderText(title: "Active")
                        Card { tripRows(activeCards) }
                    }
                    if !completedCards.isEmpty {
                        SectionHeaderText(title: "Completed")
                        Card { tripRows(completedCards) }
                    }
                }

                Spacer(minLength: FloatingActionLayout.scrollBottomClearance)
            }
            .scrollIndicators(.hidden)
            .background(Sage.bg.ignoresSafeArea())
            .refreshable { await sync.pullAll() }

            Fab(label: "Add expense", systemImage: "plus", accessibilityIdentifier: "trips.addExpenseButton") {
                onAddExpense()
            }
            .floatingActionPlacement()
        }
        .sheet(isPresented: $showingNewTrip) {
            NewTripSheet()
        }
        .alert(
            "Delete trip?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { trip in
            Button("Delete", role: .destructive) { confirmDelete(trip) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { trip in
            Text("\"\(trip.name)\" will be removed for everyone.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Trips")
                .font(.largeTitle30)
                .tracking(-0.75)
                .foregroundStyle(Sage.text)

            Spacer(minLength: 8)

            Button {
                showingNewTrip = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Sage.accent)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88))
            .accessibilityIdentifier("trips.addButton")
            .accessibilityLabel("New trip")
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func tripRows(_ cards: [TripCard]) -> some View {
        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
            SwipeToDeleteRow(
                onTap: { onSelect(card.id) },
                onTrigger: { requestDelete(for: card.id) }
            ) {
                TripCardRow(trip: card)
            }
            if index < cards.count - 1 { RowDivider() }
        }
    }

    private func requestDelete(for tripID: UUID) {
        guard let trip = tripsByID[tripID] else { return }
        pendingDeletion = trip
    }

    private func confirmDelete(_ trip: TripEntity) {
        pendingDeletion = nil
        Deletion.softDelete(trip: trip, in: context)
        Haptics.success()
        Task { await sync.pushPending() }
    }
}

private struct EmptyTripsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "suitcase")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Sage.textSecondary)
            Text("No trips yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Sage.text)
            Text("Tap + to start your first trip")
                .font(.system(size: 14))
                .foregroundStyle(Sage.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.bottom, 40)
    }
}
