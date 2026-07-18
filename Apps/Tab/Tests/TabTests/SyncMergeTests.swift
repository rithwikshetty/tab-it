import Foundation
import SwiftData
import Testing
@testable import Tab

/// Pull-merge behavior: every remote row goes through LWW + delete-wins +
/// writeID tiebreak against the local row, and pending local changes are
/// never clobbered by stale server state. Real in-memory SwiftData, no mocks.
@MainActor
@Suite("Sync pull merge")
struct SyncMergeTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    // The container must outlive every context that touches its entities.
    let container: ModelContainer

    init() throws {
        container = try TabModelContainer.makeInMemory()
    }

    private func makeContext() throws -> ModelContext {
        container.mainContext
    }

    private func tripDTO(
        id: UUID,
        name: String,
        updatedAt: Date,
        deletedAt: Date? = nil,
        writeID: UUID = UUID()
    ) -> TripDTO {
        TripDTO(
            id: id, name: name, kind: "trip", memberSignature: nil,
            createdBy: UUID(), lastActivityAt: updatedAt, createdAt: t0,
            updatedAt: updatedAt, deletedAt: deletedAt, writeID: writeID
        )
    }

    @Test("dirty local edit survives a pull of the stale server row")
    func dirtyLocalEditSurvivesStalePull() throws {
        let ctx = try makeContext()
        let tripID = UUID()
        let pushedWrite = UUID()

        // The row as the server last saw it…
        let trip = TripEntity(
            id: tripID, name: "Lisbon", createdByID: UUID(),
            updatedAt: t0, writeID: pushedWrite, pushedWriteID: pushedWrite
        )
        ctx.insert(trip)
        // …then edited offline: newer updatedAt, new writeID, pending push.
        trip.name = "Lisbon 2026"
        trip.updatedAt = t0.addingTimeInterval(120)
        trip.writeID = UUID()
        try ctx.save()

        // A pull returns the stale server copy (old name, old writeID).
        try SyncMerge.apply(
            tripDTO(id: tripID, name: "Lisbon", updatedAt: t0, writeID: pushedWrite),
            in: ctx
        )

        #expect(trip.name == "Lisbon 2026")
        #expect(trip.pushedWriteID != trip.writeID, "row must stay dirty so the edit still pushes")
    }

    @Test("clean local row always takes the remote version")
    func cleanLocalTakesRemote() throws {
        let ctx = try makeContext()
        let tripID = UUID()
        let pushedWrite = UUID()
        let trip = TripEntity(
            id: tripID, name: "Lisbon", createdByID: UUID(),
            updatedAt: t0, writeID: pushedWrite, pushedWriteID: pushedWrite
        )
        ctx.insert(trip)
        try ctx.save()

        let remoteWrite = UUID()
        try SyncMerge.apply(
            tripDTO(id: tripID, name: "Porto", updatedAt: t0.addingTimeInterval(60), writeID: remoteWrite),
            in: ctx
        )

        #expect(trip.name == "Porto")
        #expect(trip.writeID == remoteWrite)
        #expect(trip.pushedWriteID == remoteWrite)
    }

    @Test("dirty local edit older than the remote write yields")
    func dirtyOlderLocalYields() throws {
        let ctx = try makeContext()
        let tripID = UUID()
        let pushedWrite = UUID()
        let trip = TripEntity(
            id: tripID, name: "Lisbon", createdByID: UUID(),
            updatedAt: t0, writeID: pushedWrite, pushedWriteID: pushedWrite
        )
        ctx.insert(trip)
        trip.name = "Lisbon (old offline edit)"
        trip.updatedAt = t0.addingTimeInterval(30)
        trip.writeID = UUID()
        try ctx.save()

        let remoteWrite = UUID()
        try SyncMerge.apply(
            tripDTO(id: tripID, name: "Lisbon Final", updatedAt: t0.addingTimeInterval(300), writeID: remoteWrite),
            in: ctx
        )

        #expect(trip.name == "Lisbon Final")
        #expect(trip.pushedWriteID == trip.writeID, "losing edit is resolved, not re-pushed")
    }

    @Test("remote tombstone beats a dirty local edit (delete-wins)")
    func remoteTombstoneBeatsDirtyEdit() throws {
        let ctx = try makeContext()
        let tripID = UUID()
        let pushedWrite = UUID()
        let trip = TripEntity(
            id: tripID, name: "Lisbon", createdByID: UUID(),
            updatedAt: t0, writeID: pushedWrite, pushedWriteID: pushedWrite
        )
        ctx.insert(trip)
        trip.name = "Edited after someone deleted it"
        trip.updatedAt = t0.addingTimeInterval(600)
        trip.writeID = UUID()
        try ctx.save()

        try SyncMerge.apply(
            tripDTO(id: tripID, name: "Lisbon", updatedAt: t0.addingTimeInterval(60),
                    deletedAt: t0.addingTimeInterval(60), writeID: UUID()),
            in: ctx
        )

        #expect(trip.deletedAt != nil, "remote delete wins over the concurrent local edit")
    }

    @Test("local tombstone survives a newer remote edit (delete-wins)")
    func localTombstoneSurvivesRemoteEdit() throws {
        let ctx = try makeContext()
        let tripID = UUID()
        let pushedWrite = UUID()
        let trip = TripEntity(
            id: tripID, name: "Lisbon", createdByID: UUID(),
            updatedAt: t0, writeID: pushedWrite, pushedWriteID: pushedWrite
        )
        ctx.insert(trip)
        trip.deletedAt = t0.addingTimeInterval(60)
        trip.updatedAt = t0.addingTimeInterval(60)
        trip.writeID = UUID()
        try ctx.save()

        try SyncMerge.apply(
            tripDTO(id: tripID, name: "Renamed remotely", updatedAt: t0.addingTimeInterval(600), writeID: UUID()),
            in: ctx
        )

        #expect(trip.deletedAt != nil, "pending local delete is preserved until pushed")
        #expect(trip.pushedWriteID != trip.writeID)
    }

    @Test("unknown remote row is inserted clean")
    func newRemoteRowInserted() throws {
        let ctx = try makeContext()
        let tripID = UUID()
        let remoteWrite = UUID()
        try SyncMerge.apply(
            tripDTO(id: tripID, name: "Fresh", updatedAt: t0, writeID: remoteWrite),
            in: ctx
        )
        let fetched = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == tripID }
        )).first
        #expect(fetched?.name == "Fresh")
        #expect(fetched?.pushedWriteID == remoteWrite)
    }

    @Test("orphaned expense is reattached to its trip even when the local edit wins")
    func orphanedExpenseReattached() throws {
        let ctx = try makeContext()
        let tripID = UUID()
        let expenseID = UUID()
        let trip = TripEntity(id: tripID, name: "Lisbon", createdByID: UUID())
        ctx.insert(trip)

        // Expense exists locally with a dirty edit but no trip relationship —
        // the state a failed trips-pull leaves behind.
        let pushedWrite = UUID()
        let expense = ExpenseEntity(
            id: expenseID, amount: 10, currency: "EUR", descriptionText: "Dinner",
            expenseDate: t0, createdByID: UUID(), trip: nil,
            updatedAt: t0.addingTimeInterval(600), writeID: UUID(), pushedWriteID: pushedWrite
        )
        ctx.insert(expense)
        try ctx.save()

        let dto = try expenseDTO(id: expenseID, tripID: tripID, description: "Dinner", updatedAt: t0, writeID: pushedWrite)
        try SyncMerge.apply(dto, in: ctx)

        #expect(expense.trip?.id == tripID, "relationship heals on the next pull")
        #expect(expense.descriptionText == "Dinner", "stale remote content did not clobber the dirty edit")
        #expect(expense.pushedWriteID != expense.writeID)
    }

    @Test("pulled monetary amounts are normalized on insert and update")
    func pulledMoneyIsNormalized() throws {
        let ctx = try makeContext()
        let tripID = UUID()
        let expenseID = UUID()
        let payerID = UUID()
        let participantID = UUID()
        let settlementID = UUID()
        let creatorID = UUID()
        ctx.insert(TripEntity(id: tripID, name: "Lisbon", createdByID: creatorID))

        try SyncMerge.apply(
            expenseDTO(
                id: expenseID,
                tripID: tripID,
                amount: Decimal(string: "10.005")!,
                description: "Dinner",
                updatedAt: t0,
                writeID: UUID()
            ),
            in: ctx
        )
        try SyncMerge.apply(
            ExpensePaymentDTO(
                expenseID: expenseID,
                tripPersonID: payerID,
                amountPaid: Decimal(string: "10.005")!,
                paymentMode: "exact",
                createdAt: t0,
                updatedAt: t0,
                writeID: UUID()
            ),
            in: ctx
        )
        try SyncMerge.apply(
            ExpenseSplitDTO(
                expenseID: expenseID,
                tripPersonID: participantID,
                amountOwed: Decimal(string: "10.004")!,
                splitType: "exact",
                shareUnits: nil,
                percentage: nil,
                createdAt: t0,
                updatedAt: t0,
                writeID: UUID()
            ),
            in: ctx
        )
        try SyncMerge.apply(
            SettlementDTO(
                id: settlementID,
                tripID: tripID,
                fromPersonID: payerID,
                toPersonID: participantID,
                amount: Decimal(string: "0.4")!,
                currency: "JPY",
                note: nil,
                settledAt: t0,
                createdBy: creatorID,
                createdAt: t0,
                updatedAt: t0,
                deletedAt: nil,
                writeID: UUID()
            ),
            in: ctx
        )
        try ctx.save()

        let expense = try #require(ctx.fetch(FetchDescriptor<ExpenseEntity>()).first { $0.id == expenseID })
        let payment = try #require(expense.payments.first { $0.tripPersonID == payerID })
        let split = try #require(expense.splits.first { $0.tripPersonID == participantID })
        let settlement = try #require(ctx.fetch(FetchDescriptor<SettlementEntity>()).first { $0.id == settlementID })
        #expect(expense.amount == Decimal(string: "10.01")!)
        #expect(payment.amountPaid == Decimal(string: "10.01")!)
        #expect(split.amountOwed == Decimal(string: "10.00")!)
        #expect(settlement.amount == 0)

        let newer = t0.addingTimeInterval(60)
        try SyncMerge.apply(
            expenseDTO(
                id: expenseID,
                tripID: tripID,
                amount: Decimal(string: "20.004")!,
                description: "Dinner",
                updatedAt: newer,
                writeID: UUID()
            ),
            in: ctx
        )
        try SyncMerge.apply(
            ExpensePaymentDTO(
                expenseID: expenseID,
                tripPersonID: payerID,
                amountPaid: Decimal(string: "20.004")!,
                paymentMode: "exact",
                createdAt: t0,
                updatedAt: newer,
                writeID: UUID()
            ),
            in: ctx
        )
        try SyncMerge.apply(
            ExpenseSplitDTO(
                expenseID: expenseID,
                tripPersonID: participantID,
                amountOwed: Decimal(string: "20.005")!,
                splitType: "exact",
                shareUnits: nil,
                percentage: nil,
                createdAt: t0,
                updatedAt: newer,
                writeID: UUID()
            ),
            in: ctx
        )
        try SyncMerge.apply(
            SettlementDTO(
                id: settlementID,
                tripID: tripID,
                fromPersonID: payerID,
                toPersonID: participantID,
                amount: Decimal(string: "1.5")!,
                currency: "JPY",
                note: nil,
                settledAt: newer,
                createdBy: creatorID,
                createdAt: t0,
                updatedAt: newer,
                deletedAt: nil,
                writeID: UUID()
            ),
            in: ctx
        )

        #expect(expense.amount == Decimal(string: "20.00")!)
        #expect(payment.amountPaid == Decimal(string: "20.00")!)
        #expect(split.amountOwed == Decimal(string: "20.01")!)
        #expect(settlement.amount == 2)
    }

    @Test("trip created and deleted before its first push is purged, never pushed live")
    func unpushedTripTombstonePurged() throws {
        let ctx = try makeContext()
        let ghost = TripEntity(id: UUID(), name: "Ghost", createdByID: UUID())
        ctx.insert(ghost)
        ghost.deletedAt = .now
        ghost.writeID = UUID()

        let live = TripEntity(id: UUID(), name: "Live unpushed", createdByID: UUID())
        ctx.insert(live)

        let pushedWrite = UUID()
        let pushedTombstone = TripEntity(
            id: UUID(), name: "Pushed then deleted", createdByID: UUID(),
            deletedAt: .now, writeID: UUID(), pushedWriteID: pushedWrite
        )
        ctx.insert(pushedTombstone)
        try ctx.save()

        try SyncService.purgeUnpushedTripTombstones(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<TripEntity>())
        #expect(remaining.count == 2)
        #expect(!remaining.contains { $0.name == "Ghost" })
        #expect(remaining.contains { $0.name == "Live unpushed" }, "unpushed live trips still push")
        #expect(remaining.contains { $0.name == "Pushed then deleted" }, "server-known tombstones still push their delete")
    }

    private func expenseDTO(
        id: UUID,
        tripID: UUID,
        amount: Decimal = 10,
        description: String,
        updatedAt: Date,
        writeID: UUID
    ) throws -> ExpenseDTO {
        let formatter = ISO8601DateFormatter()
        let json = """
        {
          "id": "\(id.uuidString)",
          "trip_id": "\(tripID.uuidString)",
          "amount": \(amount),
          "currency": "EUR",
          "category_id": null,
          "description": "\(description)",
          "expense_date": "2026-06-01",
          "receipt_storage_path": null,
          "payment_method": "card",
          "created_by": "\(UUID().uuidString)",
          "last_edited_by": null,
          "created_at": "\(formatter.string(from: t0))",
          "updated_at": "\(formatter.string(from: updatedAt))",
          "deleted_at": null,
          "write_id": "\(writeID.uuidString)"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExpenseDTO.self, from: Data(json.utf8))
    }
}
