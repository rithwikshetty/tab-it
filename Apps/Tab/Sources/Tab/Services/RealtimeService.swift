import Foundation
import Supabase
import Realtime
import os

private let realtimeLog = Logger(subsystem: "com.example.tab", category: "realtime")

@MainActor
@Observable
final class RealtimeService {
    private let client = SupabaseClientProvider.shared
    private let sync: SyncService

    private(set) var subscribedTripID: UUID?
    private var channel: RealtimeChannelV2?
    private var streamTasks: [Task<Void, Never>] = []
    private var pullDebounce: Task<Void, Never>?
    private var subscriptionGeneration = OperationGeneration()

    init(sync: SyncService) {
        self.sync = sync
    }

    /// Subscribe to live changes on the given trip's expenses/splits/settlements/people.
    /// Any change triggers a sync pull so local SwiftData stays in sync.
    func subscribe(to tripID: UUID) async {
        let generation = subscriptionGeneration.next()
        guard client.auth.currentSession != nil else {
            await tearDownCurrentSubscription()
            return
        }
        if subscribedTripID == tripID { return }
        await tearDownCurrentSubscription()
        guard subscriptionGeneration.isCurrent(generation) else { return }

        // Each attempt gets its own topic so a stale attempt can unsubscribe
        // itself without tearing down a newer attempt for the same trip.
        let channel = client.channel("trip-\(tripID.uuidString)-\(generation)")
        let filter: RealtimePostgresFilter = .eq("trip_id", value: tripID.uuidString)

        let expenseStream = channel.postgresChange(
            AnyAction.self, schema: "public", table: "expenses", filter: filter
        )
        let settlementStream = channel.postgresChange(
            AnyAction.self, schema: "public", table: "settlements", filter: filter
        )
        let memberStream = channel.postgresChange(
            AnyAction.self, schema: "public", table: "trip_people", filter: filter
        )
        // expense_splits has no trip_id; gets updated via the parent expense pull.

        do {
            try await channel.subscribeWithError()
        } catch {
            await removeChannel(channel)
            if subscriptionGeneration.isCurrent(generation) {
                realtimeLog.error("subscribe failed: \(error.localizedDescription, privacy: .public)")
            }
            return
        }
        guard subscriptionGeneration.isCurrent(generation) else {
            await removeChannel(channel)
            return
        }
        self.channel = channel
        self.subscribedTripID = tripID

        streamTasks = [
            Task { [weak self] in
                for await _ in expenseStream { await self?.handleChange() }
            },
            Task { [weak self] in
                for await _ in settlementStream { await self?.handleChange() }
            },
            Task { [weak self] in
                for await _ in memberStream { await self?.handleChange() }
            },
        ]
    }

    func unsubscribe() async {
        _ = subscriptionGeneration.next()
        await tearDownCurrentSubscription()
    }

    private func tearDownCurrentSubscription() async {
        pullDebounce?.cancel()
        pullDebounce = nil
        streamTasks.forEach { $0.cancel() }
        streamTasks.removeAll()
        let channel = self.channel
        self.channel = nil
        self.subscribedTripID = nil
        if let channel {
            await removeChannel(channel)
        }
    }

    private func removeChannel(_ channel: RealtimeChannelV2) async {
        // `removeChannel` only unsubscribes channels already marked subscribed;
        // explicitly unsubscribe first so cancellation also tears down an
        // attempt whose subscribe task is still unwinding.
        await channel.unsubscribe()
        await client.realtimeV2.removeChannel(channel)
    }

    /// Scoped unsubscribe: only tears down if we are still subscribed to
    /// `tripID`. A view that pushed a child screen (and fired its own
    /// `onDisappear`) must not unsubscribe a subscription a newer trip already
    /// replaced. No-op when the subscription has moved on.
    func unsubscribe(from tripID: UUID) async {
        guard subscribedTripID == tripID else { return }
        await unsubscribe()
    }

    /// Debounced: another device pushing several rows lands as a burst of
    /// events, and each pull refetches every table — coalesce the burst into
    /// one pull instead of pulling per event.
    private func handleChange() async {
        pullDebounce?.cancel()
        pullDebounce = Task { [sync] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            realtimeLog.info("realtime change — pulling")
            await sync.pullAll()
        }
    }
}
