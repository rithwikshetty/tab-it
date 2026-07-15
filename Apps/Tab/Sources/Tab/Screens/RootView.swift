import SwiftUI
import SwiftData
import UIKit

enum RootTab: Hashable { case friends, trips, activity, settings }

enum Route: Hashable {
    case trip(UUID)
    case friend(FriendIdentity)
    case newExpense(UUID)
    case newNonGroupExpense
    case editExpense(tripID: UUID, expenseID: UUID)
    case expense(UUID)
    case settleUp(tripID: UUID, suggestion: SettleUpSuggestion?)
    case editSettlement(tripID: UUID, settlementID: UUID)
    case settlement(UUID)
}

enum ActivityNavigation {
    static func stack(
        for target: ActivityTarget,
        expenseIsOpenable: (UUID) -> Bool,
        settlementIsOpenable: (UUID) -> Bool
    ) -> [Route] {
        switch target {
        case .trip(let id):
            return [.trip(id)]
        case .expense(let tripID, let expenseID):
            return expenseIsOpenable(expenseID) ? [.expense(expenseID)] : [.trip(tripID)]
        case .settlement(let tripID, let settlementID):
            return settlementIsOpenable(settlementID) ? [.settlement(settlementID)] : [.trip(tripID)]
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync
    @Environment(PushService.self) private var push

    @State private var selectedTab: RootTab = .trips
    @State private var friendsPath: [Route] = []
    @State private var tripsPath: [Route] = []
    @State private var activityPath: [Route] = []
    @State private var wasBackgrounded = false

    @Query private var activities: [ActivityEntity]
    @Query private var profiles: [ProfileEntity]
    @Query private var mutes: [TripMuteEntity]
    @Query private var tripPeople: [TripPersonEntity]

    private var currentUserID: UUID? { auth.currentUser?.id }

    private var mutedTripIDs: Set<UUID> { Set(mutes.filter(\.isMuted).map(\.tripID)) }

    private var joinedAtByTrip: [UUID: Date] {
        guard let uid = currentUserID else { return [:] }
        var map: [UUID: Date] = [:]
        for person in tripPeople where person.userID == uid {
            if let tripID = person.trip?.id, let joinedAt = person.joinedAt {
                map[tripID] = joinedAt
            }
        }
        return map
    }

    private var unreadCount: Int {
        guard let uid = currentUserID else { return 0 }
        let cursor = profiles.first { $0.id == uid }?.activityLastSeenAt
        return ActivityPresenter.unreadCount(
            from: activities,
            currentUserID: uid,
            lastSeenAt: cursor,
            mutedTripIDs: mutedTripIDs,
            joinedAtByTrip: joinedAtByTrip
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Friends", systemImage: "person.2", value: RootTab.friends) {
                NavigationStack(path: $friendsPath) {
                    FriendsView(
                        onOpenFriend: { friendsPath.append(.friend($0)) },
                        onAddExpense: { friendsPath.append(.newNonGroupExpense) }
                    )
                    .navigationDestination(for: Route.self) { destination($0, path: $friendsPath) }
                }
                .toolbar(tabBarVisibility(for: friendsPath), for: .tabBar)
            }

            Tab("Trips", systemImage: "suitcase", value: RootTab.trips) {
                NavigationStack(path: $tripsPath) {
                    TripListView(
                        onSelect: { tripID in tripsPath.append(.trip(tripID)) },
                        onAddExpense: { tripsPath.append(.newNonGroupExpense) }
                    )
                        .navigationDestination(for: Route.self) { destination($0, path: $tripsPath) }
                }
                .toolbar(tabBarVisibility(for: tripsPath), for: .tabBar)
            }

            Tab("Activity", systemImage: "bell", value: RootTab.activity) {
                NavigationStack(path: $activityPath) {
                    ActivityView { target in open(target, into: $activityPath) }
                        .navigationDestination(for: Route.self) { destination($0, path: $activityPath) }
                }
                .toolbar(tabBarVisibility(for: activityPath), for: .tabBar)
            }
            .badge(unreadCount)

            Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tint(Sage.accent)
        .background(Sage.bg.ignoresSafeArea())
        .toolbarBackground(Sage.tabBarBg, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task(id: auth.currentUser) {
            removeLegacyMockSeedIfNeeded()
            bootstrapProfile()
            bootstrapDefaultCategories()
            #if DEBUG
            DebugFriendsSeed.seedIfRequested(in: context, currentUserID: currentUserID)
            DebugActivitySeed.seedIfRequested(in: context, currentUserID: currentUserID)
            DemoScreenshotSeed.seedIfRequested(in: context, currentUserID: currentUserID)
            #endif
            await sync.pushPending()
            await sync.claimTripPeopleForCurrentEmail()
            await sync.pullAll()
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["TAB_PROVISIONAL_PUSH"] == "1" {
                await push.requestProvisionalForTesting()
            } else if env["TAB_SKIP_PUSH_PROMPT"] != "1" {
                await push.requestAuthorizationAndRegister()
            }
            #else
            await push.requestAuthorizationAndRegister()
            #endif
            // Register explicitly even when the token value didn't change:
            // after an account switch on the same device APNs re-issues the
            // same token, so .onChange(of: push.deviceToken) never fires and
            // the new account would otherwise stay unregistered.
            if let token = push.deviceToken {
                await sync.registerPushDevice(token: token, deviceName: UIDevice.current.name)
            }
            // A notification tap that cold-launches the app sets lastTap before
            // this view exists, so .onChange(of: push.lastTap) never fires for
            // it — consume the pending tap here.
            if let tap = push.lastTap {
                push.lastTap = nil
                handlePushTap(tap)
            }
        }
        .onAppear {
            #if DEBUG
            switch ProcessInfo.processInfo.environment["TAB_START_TAB"] {
            case "friends": selectedTab = .friends
            case "activity": selectedTab = .activity
            case "settings": selectedTab = .settings
            default: break
            }
            #endif
        }
        .onChange(of: push.deviceToken) { _, token in
            guard let token else { return }
            Task { await sync.registerPushDevice(token: token, deviceName: UIDevice.current.name) }
        }
        .onChange(of: push.lastTap) { _, tap in
            guard let tap else { return }
            handlePushTap(tap)
            push.lastTap = nil
        }
        .onChange(of: unreadCount) { _, count in
            Task { await push.setBadgeCount(count) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Only a real return from the background warrants a catch-up sync.
            // Cold launch is already covered by the .task above, and
            // inactive→active flickers (app switcher, notification shade)
            // shouldn't each trigger a full sync. Foregrounding passes through
            // .inactive (background → inactive → active), so a "was backgrounded"
            // flag is needed — comparing against the previous phase on the
            // .active transition would only ever see .inactive.
            if phase == .background { wasBackgrounded = true }
            if phase == .active && wasBackgrounded {
                wasBackgrounded = false
                Task {
                    await sync.pushPending()
                    await sync.pullAll()
                }
                // Also pick up a notification permission the user just flipped
                // on in the Settings app — without this, pushes only start
                // after a full relaunch.
                Task { await push.registerIfAuthorized() }
            }
        }
        .onChange(of: push.lastForegroundReceipt) { _, receipt in
            // A banner shown while the app is open announces content the local
            // store may not have yet — refresh so the feed matches the banner.
            guard receipt != nil else { return }
            push.lastForegroundReceipt = nil
            Task { await sync.pullAll() }
        }
        .onAppear {
            Task { await push.setBadgeCount(unreadCount) }
        }
    }

    // MARK: - Navigation

    /// Tab bar visibility is driven by the navigation path, not by a
    /// `.toolbar(.hidden, for: .tabBar)` on each pushed screen: visibility tied
    /// to the pushed view's lifecycle only restores the bar *after* the pop
    /// transition finishes, which reads as the bar blinking back in late.
    /// Top-level lists and trip/friend detail keep the bar; deeper editor and
    /// detail screens hide it.
    private func tabBarVisibility(for path: [Route]) -> Visibility {
        switch path.last {
        case nil, .trip, .friend:
            return .visible
        default:
            return .hidden
        }
    }

    @ViewBuilder
    private func destination(_ route: Route, path: Binding<[Route]>) -> some View {
        switch route {
        case .trip(let id):
            TripDetailView(
                tripID: id,
                onAddExpense: { path.wrappedValue.append(.newExpense(id)) },
                onOpenExpense: { expenseID in path.wrappedValue.append(.expense(expenseID)) },
                onSettleUp: { suggestion in
                    path.wrappedValue.append(.settleUp(tripID: id, suggestion: suggestion))
                },
                onOpenSettlement: { settlementID in path.wrappedValue.append(.settlement(settlementID)) }
            )
        case .friend(let identity):
            FriendDetailView(
                friend: identity,
                onSettleSource: { containerID, suggestion in
                    path.wrappedValue.append(.settleUp(tripID: containerID, suggestion: suggestion))
                },
                onOpenExpense: { expenseID in path.wrappedValue.append(.expense(expenseID)) },
                onOpenSettlement: { settlementID in path.wrappedValue.append(.settlement(settlementID)) }
            )
        case .newExpense(let tripID):
            ExpenseEntryView(tripID: tripID)
        case .newNonGroupExpense:
            NonGroupExpenseFlowView(
                // Swap the picker for the expense form so saving returns to the tab root.
                onResolved: { containerID in path.wrappedValue = [.newExpense(containerID)] }
            )
        case .editExpense(let tripID, let expenseID):
            ExpenseEntryView(tripID: tripID, editingExpenseID: expenseID)
        case .expense(let expenseID):
            ExpenseDetailView(
                expenseID: expenseID,
                onEditExpense: { tripID, expenseID in
                    path.wrappedValue.append(.editExpense(tripID: tripID, expenseID: expenseID))
                }
            )
        case .settleUp(let tripID, let suggestion):
            SettleUpFormView(tripID: tripID, suggestedPayment: suggestion)
        case .editSettlement(let tripID, let settlementID):
            SettleUpFormView(tripID: tripID, editingSettlementID: settlementID)
        case .settlement(let settlementID):
            SettlementDetailView(
                settlementID: settlementID,
                onEditSettlement: { tripID, settlementID in
                    path.wrappedValue.append(.editSettlement(tripID: tripID, settlementID: settlementID))
                }
            )
        }
    }

    /// Deep-link from an Activity feed row (stays within the Activity tab's stack).
    private func open(_ target: ActivityTarget, into path: Binding<[Route]>) {
        path.wrappedValue = ActivityNavigation.stack(
            for: target,
            expenseIsOpenable: expenseIsOpenable,
            settlementIsOpenable: settlementIsOpenable
        )
    }

    /// Deep-link from a tapped push notification (opens in the Trips tab).
    /// The push usually races the sync pull, so when the target entity isn't
    /// local yet, land on the trip, pull, and only then push the detail screen
    /// — and only if the user hasn't navigated away in the meantime.
    private func handlePushTap(_ tap: PushPayload) {
        selectedTab = .trips
        let base: [Route] = [.trip(tap.tripID)]
        if let route = entityRoute(for: tap) {
            tripsPath = base + [route]
            Task { await sync.pullAll() }
            return
        }
        tripsPath = base
        Task {
            await sync.pullAll()
            if let route = entityRoute(for: tap), tripsPath == base {
                tripsPath.append(route)
            }
        }
    }

    private func entityRoute(for tap: PushPayload) -> Route? {
        guard let type = tap.entityType, let entityID = tap.entityID else { return nil }
        switch type {
        case "expense" where expenseIsOpenable(entityID):
            return .expense(entityID)
        case "settlement" where settlementIsOpenable(entityID):
            return .settlement(entityID)
        default:
            return nil
        }
    }

    private func expenseIsOpenable(_ id: UUID) -> Bool {
        ((try? context.fetch(FetchDescriptor<ExpenseEntity>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
        )))?.first) != nil
    }

    private func settlementIsOpenable(_ id: UUID) -> Bool {
        ((try? context.fetch(FetchDescriptor<SettlementEntity>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
        )))?.first) != nil
    }

    // MARK: - Bootstrap

    private func removeLegacyMockSeedIfNeeded() {
        let seedTripID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let descriptor = FetchDescriptor<TripEntity>(predicate: #Predicate<TripEntity> { $0.id == seedTripID })
        do {
            for trip in try context.fetch(descriptor) {
                context.delete(trip)
            }
            try context.save()
        } catch { }
    }

    private func bootstrapProfile() {
        guard let user = auth.currentUser else { return }
        let userID = user.id
        let descriptor = FetchDescriptor<ProfileEntity>(predicate: #Predicate { $0.id == userID })
        do {
            let existing = try context.fetch(descriptor)
            if let profile = existing.first {
                if profile.displayName != user.displayName {
                    profile.displayName = user.displayName
                    profile.updatedAt = .now
                    profile.writeID = UUID()
                    try context.save()
                }
            } else {
                context.insert(ProfileEntity(id: userID, displayName: user.displayName))
                try context.save()
            }
        } catch { }
    }

    private func bootstrapDefaultCategories() {
        let descriptor = FetchDescriptor<CategoryEntity>(predicate: #Predicate<CategoryEntity> { $0.isDefault })
        do {
            let existing = try context.fetch(descriptor)
            let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            for def in DefaultCategories.all {
                if let entity = byID[def.id] {
                    if entity.icon != def.icon { entity.icon = def.icon }
                    if entity.name != def.name { entity.name = def.name }
                } else {
                    context.insert(CategoryEntity(
                        id: def.id, tripID: nil, name: def.name, icon: def.icon, isDefault: true
                    ))
                }
            }
            try context.save()
        } catch { }
    }
}
