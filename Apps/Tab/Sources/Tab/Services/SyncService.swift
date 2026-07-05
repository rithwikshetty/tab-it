import Foundation
import SwiftData
import Supabase
import os

private let syncLog = Logger(subsystem: "com.example.tab", category: "sync")

private struct ExpensePaymentRemoteKey: Hashable, Sendable {
    let expenseID: UUID
    let tripPersonID: UUID
}

private struct ExpenseSplitRemoteKey: Hashable, Sendable {
    let expenseID: UUID
    let tripPersonID: UUID
}

@MainActor
@Observable
final class SyncService {
    enum Phase: Equatable {
        case idle
        case pulling
        case pushing
        case error(String)
    }

    enum SyncError: LocalizedError {
        case signInRequired
        case localTripMissing
        case deletedTrip
        case nonGroupResolveFailed

        var errorDescription: String? {
            switch self {
            case .signInRequired: "Sign in to sync this trip."
            case .localTripMissing: "Trip not found on this device."
            case .deletedTrip: "This trip has been deleted."
            case .nonGroupResolveFailed: "Couldn't set up this non-group expense. Check your connection and try again."
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var lastPullAt: Date?

    private let client = SupabaseClientProvider.shared
    private let container: ModelContainer
    private weak var auth: AuthService?

    init(container: ModelContainer, auth: AuthService) {
        self.container = container
        self.auth = auth
    }

    /// Returns true when a real Supabase session exists (i.e. not mock auth).
    private var hasRealSession: Bool {
        #if DEBUG
        if auth?.isUsingMockAuth == true { return false }
        #endif
        guard let session = client.auth.currentSession,
              !session.isExpired,
              let currentUserID = auth?.currentUser?.id else {
            return false
        }
        return session.user.id == currentUserID
    }

    func ensureTripUploaded(tripID: UUID) async throws {
        guard hasRealSession else { throw SyncError.signInRequired }

        let ctx = container.mainContext
        let trip = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == tripID }
        )).first

        guard let trip else { throw SyncError.localTripMissing }
        guard trip.deletedAt == nil else { throw SyncError.deletedTrip }
        guard trip.pushedWriteID != trip.writeID else { return }

        try await pushCurrentProfileIfNeeded(in: ctx)
        try await pushTrip(trip)
        try ctx.save()
    }

    func claimTripPeopleForCurrentEmail() async {
        guard hasRealSession else { return }
        do {
            try await client
                .rpc("claim_trip_people_for_current_email")
                .execute()
        } catch {
            syncLog.error("trip people claim failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func addTripPerson(tripID: UUID, email: String, displayName: String? = nil, personID: UUID = UUID()) async throws -> UUID {
        try await ensureTripUploaded(tripID: tripID)

        let row: TripPersonDTO = try await client
            .rpc("add_trip_person_by_email", params: [
                "p_trip_id": AnyJSON.string(tripID.uuidString),
                "p_email": AnyJSON.string(email),
                "p_display_name": displayName.map { AnyJSON.string($0) } ?? .null,
                "p_person_id": AnyJSON.string(personID.uuidString),
            ])
            .execute()
            .value

        let ctx = container.mainContext
        try SyncMerge.apply(row, in: ctx)
        try ctx.save()
        return row.id
    }

    /// Repoints a pending person to a real email so its owner can claim it at
    /// sign-in — the path that makes Splitwise-imported (placeholder-email)
    /// people linkable.
    func updateTripPersonEmail(personID: UUID, email: String) async throws {
        let normalized = Self.normalizedEmail(email)
        #if DEBUG
        if auth?.isUsingMockAuth == true {
            let ctx = container.mainContext
            guard let person = try ctx.fetch(FetchDescriptor<TripPersonEntity>(
                predicate: #Predicate { $0.id == personID }
            )).first else { throw SyncError.localTripMissing }
            person.email = normalized
            person.updatedAt = .now
            try ctx.save()
            return
        }
        #endif
        guard hasRealSession else { throw SyncError.signInRequired }

        let row: TripPersonDTO = try await client
            .rpc("update_trip_person_email", params: [
                "p_person_id": AnyJSON.string(personID.uuidString),
                "p_email": AnyJSON.string(normalized),
            ])
            .execute()
            .value

        let ctx = container.mainContext
        try SyncMerge.apply(row, in: ctx)
        try ctx.save()
    }

    /// Soft-removes a person from a trip. Their ledger rows and balances stay;
    /// they drop out of member lists and pickers and lose trip access.
    func removeTripPerson(personID: UUID) async throws {
        #if DEBUG
        if auth?.isUsingMockAuth == true {
            let ctx = container.mainContext
            guard let person = try ctx.fetch(FetchDescriptor<TripPersonEntity>(
                predicate: #Predicate { $0.id == personID }
            )).first else { throw SyncError.localTripMissing }
            person.removedAt = .now
            person.updatedAt = .now
            try ctx.save()
            return
        }
        #endif
        guard hasRealSession else { throw SyncError.signInRequired }

        let row: TripPersonDTO = try await client
            .rpc("remove_trip_person", params: [
                "p_person_id": AnyJSON.string(personID.uuidString),
            ])
            .execute()
            .value

        let ctx = container.mainContext
        try SyncMerge.apply(row, in: ctx)
        try ctx.save()
    }

    func suggestTripPeople(query: String? = nil) async throws -> [TripPersonSuggestionDTO] {
        guard hasRealSession else { return [] }
        return try await client
            .rpc("suggest_trip_people", params: [
                "p_query": query.map { AnyJSON.string($0) } ?? .null,
                "p_limit": AnyJSON.integer(12),
            ])
            .execute()
            .value
    }

    /// Finds or creates the hidden non-group container shared by the current user
    /// and `participants` (the other people, by email). Persists the container +
    /// its trip_people locally (server-managed; never pushed) and returns the
    /// container id so a non-group expense can be written against it.
    func resolveNonGroupContainer(participants: [(email: String, displayName: String)]) async throws -> UUID {
        guard let user = auth?.currentUser else { throw SyncError.signInRequired }

        let selfEmail = user.email.map(Self.normalizedEmail) ?? "\(user.id.uuidString.lowercased())@users.tab"
        // Normalize and dedupe inside so callers cannot create one-person or duplicate
        // local containers, and so the payload matches the RPC's server-side normalization.
        var seenEmails: Set<String> = []
        let normalized = participants.compactMap { participant -> (email: String, displayName: String)? in
            let email = Self.normalizedEmail(participant.email)
            guard email != selfEmail, seenEmails.insert(email).inserted else { return nil }
            return (email: email, displayName: participant.displayName)
        }
        guard !normalized.isEmpty else { throw SyncError.nonGroupResolveFailed }

        // Canonical participant-set signature (caller + others), stable across claim.
        var emails = Set(normalized.map { $0.email })
        emails.insert(selfEmail)
        let signature = emails.sorted().joined(separator: "|")

        // Mock auth: there is no server, so create the container locally (the rest of
        // the app works the same way under mock auth). This is mock-ONLY — a real user
        // whose session is merely expired must re-authenticate rather than create an
        // orphaned local container the server never learns about.
        var isMockAuth = false
        #if DEBUG
        isMockAuth = auth?.isUsingMockAuth == true
        #endif
        if isMockAuth {
            return try resolveNonGroupContainerLocally(
                signature: signature, selfEmail: selfEmail, user: user, participants: normalized
            )
        }
        guard hasRealSession else { throw SyncError.signInRequired }

        let payload = normalized.map { p in
            AnyJSON.object([
                "email": .string(p.email),
                "display_name": .string(p.displayName),
            ])
        }
        let rows: [TripPersonDTO] = try await client
            .rpc("resolve_or_create_non_group_container", params: [
                "p_participants": AnyJSON.array(payload)
            ])
            .execute()
            .value

        guard let containerID = rows.first?.tripID else {
            throw SyncError.nonGroupResolveFailed
        }

        let ctx = container.mainContext
        if try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == containerID }
        )).first == nil {
            // Placeholder; a subsequent pull fills authoritative fields. Marked
            // clean (pushedWriteID == writeID) so pushTrips never tries to push it.
            let write = UUID()
            ctx.insert(TripEntity(
                id: containerID,
                name: "",
                kind: "non_group",
                memberSignature: signature,
                createdByID: user.id,
                writeID: write,
                pushedWriteID: write
            ))
        }
        for dto in rows {
            try SyncMerge.apply(dto, in: ctx)
        }
        try ctx.save()
        return containerID
    }

    private func resolveNonGroupContainerLocally(
        signature: String,
        selfEmail: String,
        user: CurrentUser,
        participants: [(email: String, displayName: String)]
    ) throws -> UUID {
        let ctx = container.mainContext
        if let existing = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.kind == "non_group" && $0.memberSignature == signature && $0.deletedAt == nil }
        )).first {
            return existing.id
        }

        let write = UUID()
        let containerID = UUID()
        let trip = TripEntity(
            id: containerID, name: "", kind: "non_group", memberSignature: signature,
            createdByID: user.id, writeID: write, pushedWriteID: write
        )
        ctx.insert(trip)

        let selfWrite = UUID()
        ctx.insert(TripPersonEntity(
            id: UUID(), userID: user.id, email: selfEmail, displayName: user.displayName,
            invitedByID: user.id, trip: trip, joinedAt: .now, writeID: selfWrite, pushedWriteID: selfWrite
        ))
        for p in participants {
            let email = Self.normalizedEmail(p.email)
            if email == selfEmail { continue }
            let w = UUID()
            ctx.insert(TripPersonEntity(
                id: UUID(), userID: nil, email: email, displayName: p.displayName,
                invitedByID: user.id, trip: trip, joinedAt: nil, writeID: w, pushedWriteID: w
            ))
        }
        try ctx.save()
        return containerID
    }

    // MARK: - Pull

    private var pullInFlight = false
    private var pullQueued = false

    /// Coalesces overlapping pull requests: launch, foreground, realtime events
    /// and pull-to-refresh can all fire close together, and each full pull
    /// merges every table on the main context. While one pull runs, further
    /// requests collapse into a single trailing pull (so a change that arrives
    /// mid-pull is still picked up) instead of stacking redundant full pulls.
    func pullAll() async {
        guard hasRealSession else { return }
        if pullInFlight {
            pullQueued = true
            return
        }
        pullInFlight = true
        defer { pullInFlight = false }
        repeat {
            pullQueued = false
            await performPullAll()
        } while pullQueued
    }

    private func performPullAll() async {
        phase = .pulling

        // Pull each table independently so a failure in one (e.g. a single
        // undecodable row) can't abort the rest — every table that succeeds
        // still lands. A failed pull yields nil, which reconciliation treats as
        // "remote state unknown" and skips, so a transient fetch failure is never
        // mistaken for a remote deletion (which would wrongly delete local rows).
        var firstError: Error?
        func attempt<T>(_ table: String, _ work: () async throws -> T) async -> T? {
            do {
                return try await work()
            } catch {
                syncLog.error("\(table, privacy: .public) pull failed: \(error.localizedDescription, privacy: .public)")
                if firstError == nil { firstError = error }
                return nil
            }
        }

        let profileIDs         = await attempt("profiles") { try await self.pullProfiles() }
        let tripIDs            = await attempt("trips") { try await self.pullTrips() }
        let tripPersonIDs      = await attempt("trip_people") { try await self.pullTripPeople() }
        let categoryIDs        = await attempt("categories") { try await self.pullCategories() }
        let expenseIDs         = await attempt("expenses") { try await self.pullExpenses() }
        let expensePaymentKeys = await attempt("expense_payments") { try await self.pullExpensePayments() }
        let expenseSplitKeys   = await attempt("expense_splits") { try await self.pullExpenseSplits() }
        let settlementIDs      = await attempt("settlements") { try await self.pullSettlements() }
        let muteTripIDs        = await attempt("trip_mute_prefs") { try await self.pullMutes() }
        _                      = await attempt("activity_log") { try await self.pullActivity() }

        do {
            try reconcileLocalRows(
                remoteProfileIDs: profileIDs,
                remoteTripIDs: tripIDs,
                remoteTripPersonIDs: tripPersonIDs,
                remoteCategoryIDs: categoryIDs,
                remoteExpenseIDs: expenseIDs,
                remoteExpensePaymentKeys: expensePaymentKeys,
                remoteExpenseSplitKeys: expenseSplitKeys,
                remoteSettlementIDs: settlementIDs,
                remoteMuteTripIDs: muteTripIDs
            )
        } catch {
            syncLog.error("reconcile failed: \(error.localizedDescription, privacy: .public)")
            if firstError == nil { firstError = error }
        }

        if let firstError {
            phase = .error(firstError.localizedDescription)
        } else {
            lastPullAt = .now
            phase = .idle
        }
    }

    private func pullProfiles() async throws -> Set<UUID> {
        let rows: [ProfileDTO] = try await client
            .from("visible_profiles")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try SyncMerge.apply(dto, in: ctx)
        }
        try ctx.save()
        return Set(rows.map(\.id))
    }

    private func pullTrips() async throws -> Set<UUID> {
        let rows: [TripDTO] = try await client
            .from("trips")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try SyncMerge.apply(dto, in: ctx)
        }
        try ctx.save()
        return Set(rows.map(\.id))
    }

    private func pullTripPeople() async throws -> Set<UUID> {
        let rows: [TripPersonDTO] = try await client
            .from("trip_people")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try SyncMerge.apply(dto, in: ctx)
        }
        try ctx.save()
        return Set(rows.map(\.id))
    }

    private func pullCategories() async throws -> Set<UUID> {
        let rows: [CategoryDTO] = try await client
            .from("categories")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try SyncMerge.apply(dto, in: ctx)
        }
        try ctx.save()
        return Set(rows.map(\.id))
    }

    private func pullExpenses() async throws -> Set<UUID> {
        let rows: [ExpenseDTO] = try await client
            .from("expenses")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try SyncMerge.apply(dto, in: ctx)
        }
        try ctx.save()
        return Set(rows.map(\.id))
    }

    private func pullExpensePayments() async throws -> Set<ExpensePaymentRemoteKey> {
        let rows: [ExpensePaymentDTO] = try await client
            .from("expense_payments")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try SyncMerge.apply(dto, in: ctx)
        }
        try ctx.save()
        return Set(rows.map { ExpensePaymentRemoteKey(expenseID: $0.expenseID, tripPersonID: $0.tripPersonID) })
    }

    private func pullExpenseSplits() async throws -> Set<ExpenseSplitRemoteKey> {
        let rows: [ExpenseSplitDTO] = try await client
            .from("expense_splits")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try SyncMerge.apply(dto, in: ctx)
        }
        try ctx.save()
        return Set(rows.map { ExpenseSplitRemoteKey(expenseID: $0.expenseID, tripPersonID: $0.tripPersonID) })
    }

    private func pullSettlements() async throws -> Set<UUID> {
        let rows: [SettlementDTO] = try await client
            .from("settlements")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try SyncMerge.apply(dto, in: ctx)
        }
        try ctx.save()
        return Set(rows.map(\.id))
    }

    /// Rolling window for the Activity feed mirror (bounds local growth).
    private static let activityWindowSeconds: TimeInterval = 90 * 24 * 60 * 60

    private func pullActivity() async throws -> Set<UUID> {
        let cutoffDate = Date().addingTimeInterval(-Self.activityWindowSeconds)
        let cutoff = ISO8601DateFormatter().string(from: cutoffDate)
        let rows: [ActivityDTO] = try await client
            .from("activity_log")
            .select()
            .gte("timestamp", value: cutoff)
            .order("timestamp", ascending: false)
            .limit(300)
            .execute()
            .value

        let ctx = container.mainContext
        // One batched ID fetch instead of an existence query per pulled row.
        let existingIDs = Set(try ctx.fetch(FetchDescriptor<ActivityEntity>()).map(\.id))
        for dto in rows {
            if existingIDs.contains(dto.id) { continue }  // activity_log is append-only / immutable
            let snapshotData = dto.snapshot.flatMap { try? JSONEncoder().encode($0) }
            ctx.insert(ActivityEntity(
                id: dto.id,
                tripID: dto.tripID,
                actorID: dto.actorID,
                action: dto.action,
                entityType: dto.entityType,
                entityID: dto.entityID,
                timestamp: dto.timestamp,
                snapshotData: snapshotData
            ))
        }

        // Prune rows past the window so the local mirror stays bounded.
        for stale in try ctx.fetch(FetchDescriptor<ActivityEntity>(
            predicate: #Predicate { $0.timestamp < cutoffDate }
        )) {
            ctx.delete(stale)
        }
        try ctx.save()
        return Set(rows.map(\.id))
    }

    private func pullMutes() async throws -> Set<UUID> {
        let rows: [TripMuteDTO] = try await client
            .from("trip_mute_prefs")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try SyncMerge.apply(dto, in: ctx)
        }
        try ctx.save()
        return Set(rows.map(\.tripID))
    }

    /// Deletes local rows that the server no longer has. Each remote set is
    /// optional: `nil` means that table's pull failed this cycle, so its remote
    /// state is unknown and we skip its deletions entirely rather than risk
    /// deleting rows that still exist on the server. Parent→child relationships
    /// are `.cascade`, so deleting a remotely-removed trip/expense also clears its
    /// children locally even when the child table's own pull was skipped.
    private func reconcileLocalRows(
        remoteProfileIDs: Set<UUID>?,
        remoteTripIDs: Set<UUID>?,
        remoteTripPersonIDs: Set<UUID>?,
        remoteCategoryIDs: Set<UUID>?,
        remoteExpenseIDs: Set<UUID>?,
        remoteExpensePaymentKeys: Set<ExpensePaymentRemoteKey>?,
        remoteExpenseSplitKeys: Set<ExpenseSplitRemoteKey>?,
        remoteSettlementIDs: Set<UUID>?,
        remoteMuteTripIDs: Set<UUID>?
    ) throws {
        let ctx = container.mainContext

        if let remoteExpensePaymentKeys {
            for payment in try ctx.fetch(FetchDescriptor<PaymentEntity>()) {
                guard payment.pushedWriteID != nil, let expenseID = payment.expense?.id else { continue }
                if !remoteExpensePaymentKeys.contains(ExpensePaymentRemoteKey(expenseID: expenseID, tripPersonID: payment.tripPersonID)) {
                    ctx.delete(payment)
                }
            }
        }

        if let remoteExpenseSplitKeys {
            for split in try ctx.fetch(FetchDescriptor<ExpenseSplitEntity>()) {
                guard split.pushedWriteID != nil, let expenseID = split.expense?.id else { continue }
                if !remoteExpenseSplitKeys.contains(ExpenseSplitRemoteKey(expenseID: expenseID, tripPersonID: split.tripPersonID)) {
                    ctx.delete(split)
                }
            }
        }

        if let remoteSettlementIDs {
            for settlement in try ctx.fetch(FetchDescriptor<SettlementEntity>()) {
                if settlement.pushedWriteID != nil && !remoteSettlementIDs.contains(settlement.id) {
                    ctx.delete(settlement)
                }
            }
        }

        if let remoteExpenseIDs {
            for expense in try ctx.fetch(FetchDescriptor<ExpenseEntity>()) {
                if expense.pushedWriteID != nil && !remoteExpenseIDs.contains(expense.id) {
                    ctx.delete(expense)
                }
            }
        }

        if let remoteTripPersonIDs {
            for person in try ctx.fetch(FetchDescriptor<TripPersonEntity>()) {
                guard person.pushedWriteID != nil else { continue }
                if !remoteTripPersonIDs.contains(person.id) {
                    ctx.delete(person)
                }
            }
        }

        if let remoteTripIDs {
            for trip in try ctx.fetch(FetchDescriptor<TripEntity>()) {
                if trip.pushedWriteID != nil && !remoteTripIDs.contains(trip.id) {
                    ctx.delete(trip)
                }
            }
        }

        if let remoteCategoryIDs {
            for category in try ctx.fetch(FetchDescriptor<CategoryEntity>()) {
                guard !category.isDefault else { continue }
                if category.pushedWriteID != nil && !remoteCategoryIDs.contains(category.id) {
                    ctx.delete(category)
                }
            }
        }

        if let remoteProfileIDs {
            for profile in try ctx.fetch(FetchDescriptor<ProfileEntity>()) {
                guard profile.pushedWriteID != nil else { continue }
                if auth?.currentUser?.id == profile.id { continue }
                if !remoteProfileIDs.contains(profile.id) {
                    ctx.delete(profile)
                }
            }
        }

        // Mute prefs: a clean (pushed) local mute whose trip the server no longer
        // returns was unmuted on another device — drop it. Locally-dirty rows
        // (a pending unmute) are left for pushMutes to resolve.
        if let remoteMuteTripIDs {
            for mute in try ctx.fetch(FetchDescriptor<TripMuteEntity>()) {
                guard mute.pushedWriteID == mute.writeID, mute.isMuted else { continue }
                if !remoteMuteTripIDs.contains(mute.tripID) {
                    ctx.delete(mute)
                }
            }
        }

        // Activity rows for trips we can no longer see (left/deleted) are dropped
        // so the feed only shows accessible trips.
        if let remoteTripIDs {
            for activity in try ctx.fetch(FetchDescriptor<ActivityEntity>()) {
                if !remoteTripIDs.contains(activity.tripID) {
                    ctx.delete(activity)
                }
            }
        }

        try ctx.save()
    }

    // MARK: - Push

    /// Rows whose individual pushes failed this cycle; surfaced via `phase`
    /// instead of silently reporting a clean sync.
    private var pushFailures = 0

    func pushPending() async {
        guard hasRealSession else { return }
        phase = .pushing
        pushFailures = 0
        do {
            try await pushProfiles()
            try await pushTrips()
            try await pushSettlements()
            try await pushExpensesAndSplits()
            await pushPendingReceiptUploads()
            try await pushMutes()
            if pushFailures > 0 {
                phase = .error("\(pushFailures) change(s) failed to sync")
            } else {
                phase = .idle
            }
        } catch {
            syncLog.error("push failed: \(error.localizedDescription, privacy: .public)")
            phase = .error(error.localizedDescription)
        }
    }

    private func pushProfiles() async throws {
        let ctx = container.mainContext
        guard let currentUserID = auth?.currentUser?.id else { return }
        let dirty = try ctx.fetch(FetchDescriptor<ProfileEntity>())
            .filter { $0.id == currentUserID && $0.pushedWriteID != $0.writeID }
        guard !dirty.isEmpty else { return }

        for profile in dirty {
            do {
                try await ensureCurrentProfile(profile)
            } catch {
                pushFailures += 1
                syncLog.error("profile push failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try ctx.save()
    }

    private func pushCurrentProfileIfNeeded(in ctx: ModelContext) async throws {
        guard let userID = auth?.currentUser?.id else { throw SyncError.signInRequired }
        let profile = try ctx.fetch(FetchDescriptor<ProfileEntity>(
            predicate: #Predicate { $0.id == userID }
        )).first
        guard let profile, profile.pushedWriteID != profile.writeID else { return }
        try await ensureCurrentProfile(profile)
    }

    private func ensureCurrentProfile(_ profile: ProfileEntity) async throws {
        try await client
            .rpc("ensure_current_profile", params: [
                "p_display_name": AnyJSON.string(profile.displayName),
                "p_avatar_url": profile.avatarURL.map { AnyJSON.string($0) } ?? .null,
            ])
            .execute()
        profile.pushedWriteID = profile.writeID
    }

    /// A trip created and soft-deleted before its first successful push never
    /// existed server-side. Pushing it would create a live trip the next pull
    /// resurrects — hard-delete the local tombstone instead.
    static func purgeUnpushedTripTombstones(in ctx: ModelContext) throws {
        let tombstones = try ctx.fetch(FetchDescriptor<TripEntity>())
            .filter { $0.pushedWriteID == nil && $0.deletedAt != nil }
        guard !tombstones.isEmpty else { return }
        for trip in tombstones {
            ctx.delete(trip)
        }
        try ctx.save()
    }

    private func pushTrips() async throws {
        let ctx = container.mainContext
        try Self.purgeUnpushedTripTombstones(in: ctx)
        // Non-group containers are created and mutated server-side only (via
        // resolve_or_create_non_group_container) and pulled read-only — never pushed.
        let dirty = try ctx.fetch(FetchDescriptor<TripEntity>())
            .filter { !$0.isNonGroup && $0.pushedWriteID != $0.writeID }
        guard !dirty.isEmpty else { return }
        for trip in dirty {
            do {
                try await pushTrip(trip)
            } catch {
                pushFailures += 1
                syncLog.error("trip push failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try ctx.save()
    }

    private func pushTrip(_ trip: TripEntity) async throws {
        if trip.pushedWriteID == nil {
            guard let user = auth?.currentUser else { throw SyncError.signInRequired }
            let creatorPerson = trip.people.first { $0.userID == user.id }
            let person = creatorPerson ?? TripPersonEntity(
                userID: user.id,
                email: user.email.map(Self.normalizedEmail) ?? "\(user.id.uuidString.lowercased())@users.tab",
                displayName: user.displayName,
                invitedByID: user.id,
                trip: trip,
                joinedAt: .now
            )
            if creatorPerson == nil {
                container.mainContext.insert(person)
            }
            try await client
                .rpc("create_trip_with_self", params: [
                    "p_trip_id": AnyJSON.string(trip.id.uuidString),
                    "p_person_id": AnyJSON.string(person.id.uuidString),
                    "p_name": AnyJSON.string(trip.name),
                ])
                .execute()
            person.pushedWriteID = person.writeID
        } else {
            let update = TripUpdateDTO(
                name: trip.name,
                deletedAt: trip.deletedAt,
                updatedAt: trip.updatedAt,
                writeID: trip.writeID
            )
            try await client
                .from("trips")
                .update(update)
                .eq("id", value: trip.id.uuidString)
                .execute()
        }
        trip.pushedWriteID = trip.writeID
    }

    private func pushSettlements() async throws {
        let ctx = container.mainContext
        let dirty = try ctx.fetch(FetchDescriptor<SettlementEntity>()).filter { $0.pushedWriteID != $0.writeID }
        guard !dirty.isEmpty else { return }
        for settlement in dirty {
            if settlement.deletedAt != nil {
                if settlement.pushedWriteID == nil {
                    ctx.delete(settlement)
                } else {
                    do {
                        try await client
                            .from("settlements")
                            .update(SettlementDeleteUpdateDTO(
                                deletedAt: settlement.deletedAt,
                                updatedAt: settlement.updatedAt,
                                writeID: settlement.writeID
                            ))
                            .eq("id", value: settlement.id.uuidString)
                            .execute()
                        settlement.pushedWriteID = settlement.writeID
                    } catch {
                        pushFailures += 1
                        syncLog.error("settlement delete push failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                continue
            }
            guard let trip = settlement.trip else { continue }
            let tripID = trip.id
            // Don't push settlements under a soft-deleted trip — the server
            // validates the parent trip is active and would reject.
            if trip.deletedAt != nil { continue }
            let insert = SettlementInsertDTO(
                id: settlement.id,
                tripID: tripID,
                fromPersonID: settlement.fromPersonID,
                toPersonID: settlement.toPersonID,
                amount: settlement.amount,
                currency: settlement.currency,
                note: settlement.note,
                settledAt: settlement.settledAt,
                createdBy: settlement.createdByID,
                updatedAt: settlement.updatedAt,
                writeID: settlement.writeID
            )
            do {
                try await client.from("settlements").upsert(insert, onConflict: "id").execute()
                settlement.pushedWriteID = settlement.writeID
            } catch {
                pushFailures += 1
                syncLog.error("settlement push failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try ctx.save()
    }

    private func pushPendingReceiptUploads() async {
        let ctx = container.mainContext
        do {
            let paths = try Set(
                ctx.fetch(FetchDescriptor<ExpenseEntity>(
                    predicate: #Predicate { $0.deletedAt == nil && $0.receiptStoragePath != nil }
                ))
                .compactMap(\.receiptStoragePath)
            )
            for path in paths {
                do {
                    try await ReceiptStorage.uploadPendingReceipt(path: path)
                } catch {
                    syncLog.error("receipt upload failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            syncLog.error("pending receipt scan failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Expenses + payments + splits via the create_expense_with_payments_and_splits RPC (transactional).
    /// Soft-deletes (deletedAt != nil) bypass the RPC and use a direct UPDATE,
    /// since the RPC upserts the row + splits but ignores deleted_at.
    private func pushExpensesAndSplits() async throws {
        let ctx = container.mainContext
        let dirtyExpenses = try ctx
            .fetch(FetchDescriptor<ExpenseEntity>())
            .filter { $0.pushedWriteID != $0.writeID }
        guard !dirtyExpenses.isEmpty else { return }

        for expense in dirtyExpenses {
            guard let trip = expense.trip else { continue }
            let tripID = trip.id

            if expense.deletedAt != nil {
                if expense.pushedWriteID == nil {
                    ctx.delete(expense)
                } else if trip.deletedAt != nil {
                    // Parent trip is also (locally) soft-deleted. The DB trigger
                    // `validate_expense_row` rejects updates to `deleted_at` on
                    // expenses under deleted trips, so don't even try — mark
                    // this expense write resolved and let the trip delete carry.
                    expense.pushedWriteID = expense.writeID
                } else {
                    do {
                        try await client
                            .from("expenses")
                            .update(ExpenseDeleteUpdateDTO(
                                deletedAt: expense.deletedAt,
                                updatedAt: expense.updatedAt,
                                writeID: expense.writeID
                            ))
                            .eq("id", value: expense.id.uuidString)
                            .execute()
                        expense.pushedWriteID = expense.writeID
                    } catch {
                        pushFailures += 1
                        syncLog.error("expense delete push failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                continue
            }

            // Don't push new/edited expenses under a soft-deleted trip — the
            // server's RPC validates the parent trip is active and would reject.
            if trip.deletedAt != nil { continue }

            let expensePayload: [String: AnyJSON] = [
                "id": .string(expense.id.uuidString),
                "trip_id": .string(tripID.uuidString),
                "amount": .string(Self.decimalString(expense.amount)),
                "currency": .string(expense.currency),
                "category_id": expense.categoryID.map { .string($0.uuidString) } ?? .null,
                "description": .string(expense.descriptionText),
                "expense_date": .string(ExpenseDates.serialized(expense.expenseDate)),
                "receipt_storage_path": expense.receiptStoragePath.map { .string($0) } ?? .null,
                "payment_method": .string(expense.paymentMethodRaw),
                "created_by": .string(expense.createdByID.uuidString),
                "last_edited_by": expense.lastEditedByID.map { .string($0.uuidString) } ?? .null,
                "updated_at": .string(Self.timestampFormatter.string(from: expense.updatedAt)),
                "write_id": .string(expense.writeID.uuidString),
            ]

            let paymentsPayload: [AnyJSON] = expense.payments.map { payment in
                AnyJSON.object([
                    "trip_person_id": .string(payment.tripPersonID.uuidString),
                    "amount_paid": .string(Self.decimalString(payment.amountPaid)),
                    "payment_mode": .string(payment.paymentModeRaw),
                    "updated_at": .string(Self.timestampFormatter.string(from: payment.updatedAt)),
                    "write_id": .string(payment.writeID.uuidString),
                ])
            }

            let splitsPayload: [AnyJSON] = expense.splits.map { split in
                AnyJSON.object([
                    "trip_person_id": .string(split.tripPersonID.uuidString),
                    "amount_owed": .string(Self.decimalString(split.amountOwed)),
                    "split_type": .string(split.splitTypeRaw),
                    "share_units": split.shareUnits.map { AnyJSON.string(Self.decimalString($0)) } ?? .null,
                    "percentage": split.percentage.map { AnyJSON.string(Self.decimalString($0)) } ?? .null,
                    "updated_at": .string(Self.timestampFormatter.string(from: split.updatedAt)),
                    "write_id": .string(split.writeID.uuidString),
                ])
            }

            do {
                try await client.rpc("create_expense_with_payments_and_splits", params: [
                    "p_expense":  AnyJSON.object(expensePayload),
                    "p_payments": AnyJSON.array(paymentsPayload),
                    "p_splits":   AnyJSON.array(splitsPayload),
                ]).execute()
                expense.pushedWriteID = expense.writeID
                for payment in expense.payments { payment.pushedWriteID = payment.writeID }
                for split in expense.splits { split.pushedWriteID = split.writeID }
            } catch {
                pushFailures += 1
                syncLog.error("expense push failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try ctx.save()
    }

    private func pushMutes() async throws {
        let ctx = container.mainContext
        guard let userID = auth?.currentUser?.id else { return }
        let dirty = try ctx.fetch(FetchDescriptor<TripMuteEntity>()).filter { $0.pushedWriteID != $0.writeID }
        guard !dirty.isEmpty else { return }
        for mute in dirty {
            // Snapshot the write we are pushing. If the user re-toggles during the
            // network call, writeID changes and we leave the row dirty so the next
            // pushMutes resolves the newer state (LWW convergence).
            let target = mute.writeID
            do {
                if mute.isMuted {
                    try await client.from("trip_mute_prefs")
                        .upsert(TripMuteInsertDTO(tripID: mute.tripID, userID: userID), onConflict: "trip_id,user_id")
                        .execute()
                    if mute.writeID == target { mute.pushedWriteID = target }
                } else {
                    try await client.from("trip_mute_prefs")
                        .delete()
                        .eq("trip_id", value: mute.tripID.uuidString)
                        .eq("user_id", value: userID.uuidString)
                        .execute()
                    if mute.writeID == target { ctx.delete(mute) }  // unmute tombstone resolved
                }
            } catch {
                pushFailures += 1
                syncLog.error("mute push failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try ctx.save()
    }

    // MARK: - Notifications

    /// Advances the local read cursor immediately (clears the badge), then persists
    /// it server-side. The optimistic local write also covers mock auth (no session).
    func markActivitySeen() async {
        let ctx = container.mainContext
        guard let userID = auth?.currentUser?.id else { return }
        let now = Date.now
        let profile = (try? ctx.fetch(FetchDescriptor<ProfileEntity>(
            predicate: #Predicate { $0.id == userID }
        )))?.first
        for activity in (try? ctx.fetch(FetchDescriptor<ActivityEntity>(
            predicate: #Predicate { $0.readAt == nil }
        ))) ?? [] {
            activity.readAt = now
        }
        profile?.activityLastSeenAt = maxDate(profile?.activityLastSeenAt, now)
        try? ctx.save()

        guard hasRealSession else { return }
        do {
            let serverSeenAt: Date = try await client.rpc("mark_activity_seen").execute().value
            profile?.activityLastSeenAt = maxDate(profile?.activityLastSeenAt, serverSeenAt)
            try? ctx.save()
        } catch {
            syncLog.error("mark_activity_seen failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    /// Registers (or refreshes) this device's APNs token. Idempotent on (user, token);
    /// called on every launch so reinstalls and token rotation self-heal.
    func registerPushDevice(token: String, deviceName: String?) async {
        guard hasRealSession, let userID = auth?.currentUser?.id else { return }
        do {
            try await client.from("push_devices")
                .upsert(
                    PushDeviceInsertDTO(userID: userID, apnsToken: token, deviceName: deviceName),
                    onConflict: "user_id,apns_token"
                )
                .execute()
        } catch {
            syncLog.error("push device register failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Toggles per-trip mute locally (offline-first) and pushes the change.
    func setTripMuted(tripID: UUID, muted: Bool) {
        let ctx = container.mainContext
        let existing = (try? ctx.fetch(FetchDescriptor<TripMuteEntity>(
            predicate: #Predicate { $0.tripID == tripID }
        )))?.first
        if let entity = existing {
            entity.isMuted = muted
            entity.updatedAt = .now
            entity.writeID = UUID()
        } else if muted {
            ctx.insert(TripMuteEntity(tripID: tripID, isMuted: true))
        } else {
            return
        }
        try? ctx.save()
        Task { try? await pushMutes() }
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
