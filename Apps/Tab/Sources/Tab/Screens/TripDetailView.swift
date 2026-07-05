import SwiftUI
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

struct TripDetailView: View {
    let tripID: UUID
    var onAddExpense: () -> Void = {}
    var onOpenExpense: (UUID) -> Void = { _ in }
    var onSettleUp: () -> Void = {}
    var onOpenSettlement: (UUID) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(RealtimeService.self) private var realtime
    @Environment(SyncService.self) private var sync

    @Query private var trips: [TripEntity]
    @Query private var categories: [CategoryEntity]
    @Query private var muteRows: [TripMuteEntity]

    @State private var segment: Int = 0
    @State private var showingPeople: Bool = false
    @State private var showingEditDetails: Bool = false

    // Derived view-state is memoised. The balance summaries, expense timeline,
    // overview, and export workbook are all O(expenses x splits) to build and
    // run on the main actor. Computing them inline in `body` meant every
    // unrelated re-render — and there are ~10 of them during the launch sync
    // pull, plus one per scroll-driven invalidation — re-ran the full set
    // synchronously, which is what froze the Expenses tab. Instead they are
    // recomputed once in `recomputeDerived(for:)`, driven by `.task(id:)` keyed
    // on a cheap content signature, and read here from these snapshots. Sync
    // saves that change nothing leave the signature untouched, so they trigger
    // no recompute at all.
    @State private var summaries: [BalanceSummary] = []
    @State private var timeline: [TimelineDay] = []
    @State private var overview: OverviewState = .empty
    @State private var exportData: TripExporter.ExportData?
    @State private var derivedLoaded = false

    init(
        tripID: UUID,
        onAddExpense: @escaping () -> Void = {},
        onOpenExpense: @escaping (UUID) -> Void = { _ in },
        onSettleUp: @escaping () -> Void = {},
        onOpenSettlement: @escaping (UUID) -> Void = { _ in }
    ) {
        self.tripID = tripID
        self.onAddExpense = onAddExpense
        self.onOpenExpense = onOpenExpense
        self.onSettleUp = onSettleUp
        self.onOpenSettlement = onOpenSettlement
        _trips = Query(filter: #Predicate<TripEntity> { $0.id == tripID })
        _muteRows = Query(filter: #Predicate<TripMuteEntity> { $0.tripID == tripID })
    }

    private var trip: TripEntity? { trips.first }

    private var isMuted: Bool { muteRows.first?.isMuted ?? false }

    private var categoriesByID: [UUID: CategoryEntity] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            if let trip, trip.deletedAt == nil {
                content(for: trip)
            } else {
                MissingTripView { dismiss() }
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: tripID) {
            await realtime.subscribe(to: tripID)
        }
        .onDisappear {
            // Scoped so pushing a child screen (which also fires onDisappear)
            // can't tear down this trip's live subscription, and a fast switch
            // to another trip can't have its subscription killed by ours.
            Task { [tripID] in await realtime.unsubscribe(from: tripID) }
        }
    }

    @ViewBuilder
    private func content(for trip: TripEntity) -> some View {
        let currentPersonID = resolvedPersonID(for: trip)
        let memberCards = trip.activePeople.sortedForDisplay(currentPersonID: currentPersonID).map { person -> MemberCard in
            if person.id == currentPersonID {
                return MemberCard(id: person.id, displayName: "You", avatarName: auth.currentUser?.displayName ?? person.displayName)
            }
            return MemberCard(id: person.id, displayName: person.displayName)
        }

        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                HStack(alignment: .center, spacing: 12) {
                    Text(trip.name)
                        .font(.largeTitle30)
                        .tracking(-0.75)
                        .foregroundStyle(Sage.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    AvatarGroup(
                        members: memberCards,
                        size: 34,
                        borderWidth: 2.5,
                        maxVisible: 5,
                        onAddTap: { showingPeople = true }
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 14)

                if !summaries.isEmpty {
                    ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                        BalanceCard(summary: summary)
                    }
                } else if derivedLoaded {
                    EmptyBalanceCard()
                }

                Segmented(options: ["Expenses", "Balances", "Overview"], selection: $segment)
                    .padding(.top, 2)
                    .padding(.bottom, 16)

                if segment == 0 {
                    timelineSection(days: timeline)
                } else if segment == 1 {
                    balancesSection(summaries: summaries)
                } else {
                    OverviewView(state: overview)
                }

                Spacer(minLength: FloatingActionLayout.scrollBottomClearance)
            }
            .scrollIndicators(.hidden)
            .refreshable { await sync.pullAll() }

            Fab(
                label: "Add expense",
                systemImage: "plus",
                accessibilityIdentifier: "trip.addExpenseButton",
                action: onAddExpense
            )
                .floatingActionPlacement()
        }
        .task(id: contentSignature(for: trip)) {
            recomputeDerived(for: trip)
        }
        .sheet(isPresented: $showingPeople) {
            TripPeopleSheet(tripID: trip.id, tripName: trip.name)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingEditDetails) {
            EditTripSheet(tripID: trip.id)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditDetails = true
                    } label: {
                        Label("Edit details", systemImage: "pencil")
                    }
                    Button {
                        onSettleUp()
                    } label: {
                        Label("Settle up", systemImage: "arrow.right.arrow.left")
                    }
                    Button {
                        Haptics.light()
                        sync.setTripMuted(tripID: trip.id, muted: !isMuted)
                    } label: {
                        Label(
                            isMuted ? "Unmute notifications" : "Mute notifications",
                            systemImage: isMuted ? "bell.slash" : "bell"
                        )
                    }
                    ShareLink(
                        item: TripExportTransferable(data: exportData ?? buildExportData(for: trip)),
                        preview: SharePreview("\(trip.name) Expenses")
                    ) {
                        Label("Export to Excel", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Sage.accent)
                        .frame(width: 32, height: 32)
                }
                .accessibilityIdentifier("tripDetail.actionsButton")
            }
        }
    }

    private func resolvedPersonID(for trip: TripEntity) -> UUID {
        let userID = auth.currentUser?.id ?? UUID()
        return trip.people.first(where: { $0.userID == userID })?.id ?? UUID()
    }

    /// Cheap fingerprint of everything the derived snapshots depend on. It reads
    /// only top-level columns on rows the context already holds, so building it
    /// never runs a presenter or re-faults the store on a warm render. The
    /// `.task(id:)` recomputes the snapshots only when this value changes, so a
    /// sync save that alters nothing relevant (the last-write-wins no-op path,
    /// or a bare server `lastActivityAt` bump) yields an identical signature and
    /// triggers no recompute.
    private func contentSignature(for trip: TripEntity) -> TripContentSignature {
        var maxExpenseStamp = Date.distantPast
        var deletedExpenses = 0
        var childCount = 0
        var maxChildStamp = Date.distantPast
        for expense in trip.expenses {
            if expense.updatedAt > maxExpenseStamp { maxExpenseStamp = expense.updatedAt }
            if expense.deletedAt != nil { deletedExpenses += 1 }
            for payment in expense.payments {
                childCount += 1
                if payment.updatedAt > maxChildStamp { maxChildStamp = payment.updatedAt }
            }
            for split in expense.splits {
                childCount += 1
                if split.updatedAt > maxChildStamp { maxChildStamp = split.updatedAt }
            }
        }
        var maxSettlementStamp = Date.distantPast
        var deletedSettlements = 0
        for settlement in trip.settlements {
            if settlement.updatedAt > maxSettlementStamp { maxSettlementStamp = settlement.updatedAt }
            if settlement.deletedAt != nil { deletedSettlements += 1 }
        }
        var maxPersonStamp = Date.distantPast
        for person in trip.people where person.updatedAt > maxPersonStamp { maxPersonStamp = person.updatedAt }
        var maxCategoryStamp = Date.distantPast
        for category in categories where category.updatedAt > maxCategoryStamp { maxCategoryStamp = category.updatedAt }

        return TripContentSignature(
            currentPersonID: resolvedPersonID(for: trip),
            currentUserName: auth.currentUser?.displayName ?? "",
            tripUpdatedAt: trip.updatedAt,
            expenseCount: trip.expenses.count,
            deletedExpenses: deletedExpenses,
            maxExpenseStamp: maxExpenseStamp,
            childCount: childCount,
            maxChildStamp: maxChildStamp,
            settlementCount: trip.settlements.count,
            deletedSettlements: deletedSettlements,
            maxSettlementStamp: maxSettlementStamp,
            peopleCount: trip.people.count,
            maxPersonStamp: maxPersonStamp,
            categoryCount: categories.count,
            maxCategoryStamp: maxCategoryStamp
        )
    }

    /// Rebuilds every derived snapshot in one pass. Runs on the main actor (the
    /// presenters are `@MainActor` and SwiftData entities are main-actor bound),
    /// but only once per content change rather than once per render.
    private func recomputeDerived(for trip: TripEntity) {
        let currentPersonID = resolvedPersonID(for: trip)
        let peopleByID = Dictionary(uniqueKeysWithValues: trip.people.map { ($0.id, $0) })

        summaries = BalancePresenter.summaries(
            expenses: trip.expenses,
            settlements: trip.settlements,
            people: trip.people,
            currentPersonID: currentPersonID,
            personFor: { id in peopleByID[id] }
        )
        timeline = timelineDays(for: trip, currentPersonID: currentPersonID, peopleByID: peopleByID)
        overview = overviewState(for: trip, currentPersonID: currentPersonID, peopleByID: peopleByID)
        exportData = buildExportData(for: trip)
        derivedLoaded = true
    }

    private func timelineDays(
        for trip: TripEntity,
        currentPersonID: UUID,
        peopleByID: [UUID: TripPersonEntity]
    ) -> [TimelineDay] {
        TimelinePresenter.days(
            expenses: trip.expenses,
            settlements: trip.settlements,
            currentPersonID: currentPersonID,
            personFor: { id in peopleByID[id] },
            categoryFor: { id in id.flatMap { categoriesByID[$0] } }
        )
    }

    private func overviewState(
        for trip: TripEntity,
        currentPersonID: UUID,
        peopleByID: [UUID: TripPersonEntity]
    ) -> OverviewState {
        OverviewPresenter.overview(
            expenses: trip.expenses,
            currentPersonID: currentPersonID,
            personName: { id in peopleByID[id]?.displayName ?? "Member" },
            categoryName: { id in id.flatMap { categoriesByID[$0]?.name } ?? "Other" }
        )
    }

    @ViewBuilder
    private func timelineSection(days: [TimelineDay]) -> some View {
        if !days.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(days) { day in
                    Text(day.dateLabel.uppercased())
                        .font(.dateHeader)
                        .tracking(1.32)
                        .foregroundStyle(Sage.textSecondary)
                        .padding(.horizontal, 26)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(timelineBlocks(for: day.items)) { block in
                        switch block {
                        case .expenses(_, let expenseItems):
                            // A block is one bounded card already realised by the
                            // outer LazyVStack, so its rows use a plain VStack —
                            // nesting a second LazyVStack here added layout cost
                            // without any virtualisation benefit.
                            VStack(spacing: 0) {
                                ForEach(expenseItems) { e in
                                    Button {
                                        Haptics.light()
                                        onOpenExpense(e.id)
                                    } label: {
                                        ExpenseRow(item: e)
                                    }
                                    .buttonStyle(.plain)
                                    if e.id != expenseItems.last?.id { RowDivider() }
                                }
                            }
                            .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Sage.cardBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 18)
                            .padding(.bottom, 6)

                        case .settlement(let s):
                            Button {
                                Haptics.light()
                                onOpenSettlement(s.id)
                            } label: {
                                SettlementRow(item: s)
                            }
                            .buttonStyle(.plain)
                            .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Sage.Avatar.slate.opacity(0.18), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 18)
                            .padding(.bottom, 6)
                        }
                    }
                }
            }
        } else if derivedLoaded {
            VStack(spacing: 6) {
                Text("No expenses yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Sage.text)
                Text("Tap + to log your first one")
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
        }
    }

    @ViewBuilder
    private func balancesSection(summaries: [BalanceSummary]) -> some View {
        if !summaries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(summary.label + " · " + summary.amount)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Sage.text)
                                .padding(.bottom, 4)
                            ForEach(summary.details) { detail in
                                HStack {
                                    Text(detail.counterparty)
                                        .font(.balanceDetail)
                                        .foregroundStyle(Sage.text.opacity(0.78))
                                    Spacer()
                                    Text(detail.amount)
                                        .font(.balanceDetail.weight(.semibold))
                                        .foregroundStyle(Sage.text)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
        } else if derivedLoaded {
            VStack(spacing: 6) {
                Text("Everyone's settled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Sage.text)
                Text("Balances will appear here once you have expenses")
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
    }
}

private enum TimelineBlock: Identifiable {
    case expenses(id: String, items: [ExpenseRowItem])
    case settlement(SettlementRowItem)

    var id: String {
        switch self {
        case .expenses(let id, _):
            id
        case .settlement(let item):
            "settlement-\(item.id.uuidString)"
        }
    }
}

extension TripDetailView {
    private func timelineBlocks(for items: [TimelineItem]) -> [TimelineBlock] {
        var blocks: [TimelineBlock] = []
        var expenseRun: [ExpenseRowItem] = []

        func flushExpenses() {
            guard !expenseRun.isEmpty else { return }
            blocks.append(.expenses(id: TimelineBlock.expenseRunID(for: expenseRun), items: expenseRun))
            expenseRun = []
        }

        for item in items {
            switch item {
            case .expense(let expense):
                expenseRun.append(expense)
            case .settlement(let settlement):
                flushExpenses()
                blocks.append(.settlement(settlement))
            }
        }

        flushExpenses()
        return blocks
    }

    /// Builds the export workbook. Kept off the per-render path: the result is
    /// memoised in `exportData` by `recomputeDerived(for:)`, and the toolbar's
    /// `ShareLink` only falls back to a live build before the first snapshot
    /// lands (i.e. if the menu is opened within the first frame).
    fileprivate func buildExportData(for trip: TripEntity) -> TripExporter.ExportData {
        let peopleByID = Dictionary(uniqueKeysWithValues: trip.people.map { ($0.id, $0) })
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return TripExporter.extractData(
            trip: trip,
            categories: categoriesByID,
            peopleByID: peopleByID
        )
    }
}

/// Cheap, value-typed fingerprint of a trip's derived-state inputs. Equality is
/// synthesised over the stored fields; `TripDetailView` recomputes its snapshots
/// only when this changes (see `contentSignature(for:)`).
private struct TripContentSignature: Equatable {
    let currentPersonID: UUID
    let currentUserName: String
    let tripUpdatedAt: Date
    let expenseCount: Int
    let deletedExpenses: Int
    let maxExpenseStamp: Date
    let childCount: Int
    let maxChildStamp: Date
    let settlementCount: Int
    let deletedSettlements: Int
    let maxSettlementStamp: Date
    let peopleCount: Int
    let maxPersonStamp: Date
    let categoryCount: Int
    let maxCategoryStamp: Date
}

private extension TimelineBlock {
    static func expenseRunID(for items: [ExpenseRowItem]) -> String {
        guard let first = items.first else { return "expenses-empty" }
        let last = items.last?.id ?? first.id
        return "expenses-\(first.id.uuidString)-\(last.uuidString)-\(items.count)"
    }
}

private struct TripExportTransferable: Transferable {
    let data: TripExporter.ExportData

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .xlsx) { item in
            SentTransferredFile(try TripExporter.generateXLSX(from: item.data))
        }
    }
}

private extension UTType {
    static var xlsx: UTType {
        UTType(filenameExtension: "xlsx")
            ?? UTType("org.openxmlformats.spreadsheetml.sheet")
            ?? .spreadsheet
    }
}

private struct MissingTripView: View {
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(Sage.textSecondary)
            Text("Trip not found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Sage.text)
            Button("Back to trips") { onBack() }
                .font(.system(size: 15))
                .foregroundStyle(Sage.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
