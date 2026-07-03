#if DEBUG
import Foundation
import SwiftData

/// Seeds sample Activity rows for local verification under mock auth (where the
/// real sync is disabled). Gated behind the `TAB_SEED_ACTIVITY=1` launch env so
/// it never runs in normal use. Rows are attributed to a fake actor so they are
/// not filtered out as the current user's own actions.
enum DebugActivitySeed {
    static let fakeActorID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    static func seedIfRequested(in context: ModelContext, currentUserID: UUID?) {
        guard ProcessInfo.processInfo.environment["TAB_SEED_ACTIVITY"] == "1" else { return }

        // Wipe and reseed so repeated seeded launches (manual runs, UI tests)
        // always start from the same five unread rows. Read state lives on the
        // rows and the profile cursor, so both are reset.
        for existing in (try? context.fetch(FetchDescriptor<ActivityEntity>())) ?? [] {
            context.delete(existing)
        }
        if let uid = currentUserID {
            let profiles = (try? context.fetch(FetchDescriptor<ProfileEntity>(
                predicate: #Predicate { $0.id == uid }
            ))) ?? []
            for profile in profiles { profile.activityLastSeenAt = nil }
        }

        // Attach to an existing local trip if there is one (enables deep-link),
        // otherwise use a stable fake trip id so the feed still renders.
        let trip = (try? context.fetch(FetchDescriptor<TripEntity>()))?.first { $0.deletedAt == nil }
        let tripID = trip?.id ?? UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let tripName = trip?.name ?? "Goa Trip"
        let now = Date()

        func encode(_ dict: [String: String]) -> Data? { try? JSONEncoder().encode(dict) }

        let samples: [(action: String, entityType: String, ago: TimeInterval, snapshot: [String: String])] = [
            ("expense_created", "expense", 60 * 20, ["actor_name": "Bo", "trip_name": tripName, "description": "Beach dinner", "amount": "84.00", "currency": "EUR"]),
            ("settlement_created", "settlement", 60 * 90, ["actor_name": "Cy", "trip_name": tripName, "from_name": "Cy", "to_name": "You", "amount": "20.00", "currency": "EUR"]),
            ("expense_updated", "expense", 60 * 60 * 26, ["actor_name": "Bo", "trip_name": tripName, "description": "Taxi to airport", "amount": "32.50", "currency": "EUR"]),
            ("member_joined", "member", 60 * 60 * 27, ["actor_name": "Bo", "trip_name": tripName, "member_name": "Dana"]),
            ("expense_deleted", "expense", 60 * 60 * 50, ["actor_name": "Cy", "trip_name": tripName, "description": "Duplicate lunch", "amount": "15.00", "currency": "EUR"]),
        ]

        for sample in samples {
            context.insert(ActivityEntity(
                id: UUID(),
                tripID: tripID,
                actorID: fakeActorID,
                action: sample.action,
                entityType: sample.entityType,
                entityID: UUID(),
                timestamp: now.addingTimeInterval(-sample.ago),
                snapshotData: encode(sample.snapshot)
            ))
        }
        try? context.save()
    }
}
#endif
