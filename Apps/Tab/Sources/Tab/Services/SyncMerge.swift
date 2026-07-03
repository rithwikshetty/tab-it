import Foundation
import SwiftData
import TabCore

/// Applies pulled server rows to local SwiftData under the app's conflict
/// policy: last-write-wins with delete-wins and a writeID tiebreaker
/// (TabCore's `ConflictResolver`). A clean local row always takes the remote
/// version; a dirty local row (pending push) is only overwritten when the
/// remote write genuinely wins — so offline edits survive pulls.
@MainActor
enum SyncMerge {
    private static func shouldApplyRemote(
        localUpdatedAt: Date,
        localDeletedAt: Date?,
        localWriteID: UUID,
        localPushedWriteID: UUID?,
        remoteUpdatedAt: Date,
        remoteDeletedAt: Date?,
        remoteWriteID: UUID
    ) -> Bool {
        ConflictResolver.merge(
            local: WriteStamp(updatedAt: localUpdatedAt, deletedAt: localDeletedAt, writeID: localWriteID),
            localIsDirty: localPushedWriteID != localWriteID,
            remote: WriteStamp(updatedAt: remoteUpdatedAt, deletedAt: remoteDeletedAt, writeID: remoteWriteID)
        ) == .applyRemote
    }

    // MARK: - Profiles

    static func apply(_ dto: ProfileDTO, in ctx: ModelContext) throws {
        let id = dto.id
        guard let entity = try ctx.fetch(FetchDescriptor<ProfileEntity>(
            predicate: #Predicate { $0.id == id }
        )).first else {
            ctx.insert(ProfileEntity(
                id: dto.id,
                displayName: dto.displayName,
                avatarURL: dto.avatarURL,
                activityLastSeenAt: dto.activityLastSeenAt,
                updatedAt: dto.updatedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
            return
        }
        guard shouldApplyRemote(
            localUpdatedAt: entity.updatedAt, localDeletedAt: nil,
            localWriteID: entity.writeID, localPushedWriteID: entity.pushedWriteID,
            remoteUpdatedAt: dto.updatedAt, remoteDeletedAt: nil, remoteWriteID: dto.writeID
        ) else { return }
        entity.displayName = dto.displayName
        entity.avatarURL = dto.avatarURL
        entity.activityLastSeenAt = maxDate(entity.activityLastSeenAt, dto.activityLastSeenAt)
        entity.updatedAt = dto.updatedAt
        entity.writeID = dto.writeID
        entity.pushedWriteID = dto.writeID
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
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

    // MARK: - Trips

    static func apply(_ dto: TripDTO, in ctx: ModelContext) throws {
        let id = dto.id
        guard let entity = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == id }
        )).first else {
            ctx.insert(TripEntity(
                id: dto.id,
                name: dto.name,
                kind: dto.kind,
                memberSignature: dto.memberSignature,
                createdByID: dto.createdBy,
                lastActivityAt: dto.lastActivityAt,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                deletedAt: dto.deletedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
            return
        }
        guard shouldApplyRemote(
            localUpdatedAt: entity.updatedAt, localDeletedAt: entity.deletedAt,
            localWriteID: entity.writeID, localPushedWriteID: entity.pushedWriteID,
            remoteUpdatedAt: dto.updatedAt, remoteDeletedAt: dto.deletedAt, remoteWriteID: dto.writeID
        ) else {
            // The server bumps last_activity_at via triggers without the row
            // being a user edit; surface it even when the local edit wins.
            if dto.lastActivityAt > entity.lastActivityAt {
                entity.lastActivityAt = dto.lastActivityAt
            }
            return
        }
        entity.name = dto.name
        entity.kind = dto.kind
        entity.memberSignature = dto.memberSignature
        entity.createdByID = dto.createdBy
        entity.lastActivityAt = dto.lastActivityAt
        entity.updatedAt = dto.updatedAt
        entity.deletedAt = dto.deletedAt
        entity.writeID = dto.writeID
        entity.pushedWriteID = dto.writeID
    }

    // MARK: - Trip people

    static func apply(_ dto: TripPersonDTO, in ctx: ModelContext) throws {
        let tripID = dto.tripID
        let id = dto.id
        guard let trip = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == tripID }
        )).first else { return }

        guard let entity = try ctx.fetch(FetchDescriptor<TripPersonEntity>(
            predicate: #Predicate { $0.id == id }
        )).first else {
            ctx.insert(TripPersonEntity(
                id: dto.id,
                userID: dto.userID,
                email: dto.email,
                displayName: dto.displayName,
                invitedByID: dto.invitedBy,
                trip: trip,
                joinedAt: dto.joinedAt,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
            return
        }
        guard shouldApplyRemote(
            localUpdatedAt: entity.updatedAt, localDeletedAt: nil,
            localWriteID: entity.writeID, localPushedWriteID: entity.pushedWriteID,
            remoteUpdatedAt: dto.updatedAt, remoteDeletedAt: nil, remoteWriteID: dto.writeID
        ) else { return }
        entity.userID = dto.userID
        entity.email = dto.email
        entity.displayName = dto.displayName
        entity.invitedByID = dto.invitedBy
        entity.joinedAt = dto.joinedAt
        entity.createdAt = dto.createdAt
        entity.updatedAt = dto.updatedAt
        entity.writeID = dto.writeID
        entity.pushedWriteID = dto.writeID
    }

    // MARK: - Categories

    static func apply(_ dto: CategoryDTO, in ctx: ModelContext) throws {
        let id = dto.id
        guard let entity = try ctx.fetch(FetchDescriptor<CategoryEntity>(
            predicate: #Predicate { $0.id == id }
        )).first else {
            ctx.insert(CategoryEntity(
                id: dto.id,
                tripID: dto.tripID,
                name: dto.name,
                icon: dto.icon,
                isDefault: dto.isDefault,
                updatedAt: dto.updatedAt,
                deletedAt: dto.deletedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
            return
        }
        guard shouldApplyRemote(
            localUpdatedAt: entity.updatedAt, localDeletedAt: entity.deletedAt,
            localWriteID: entity.writeID, localPushedWriteID: entity.pushedWriteID,
            remoteUpdatedAt: dto.updatedAt, remoteDeletedAt: dto.deletedAt, remoteWriteID: dto.writeID
        ) else { return }
        entity.name = dto.name
        entity.icon = dto.icon
        entity.isDefault = dto.isDefault
        entity.tripID = dto.tripID
        entity.updatedAt = dto.updatedAt
        entity.deletedAt = dto.deletedAt
        entity.writeID = dto.writeID
        entity.pushedWriteID = dto.writeID
    }

    // MARK: - Expenses

    static func apply(_ dto: ExpenseDTO, in ctx: ModelContext) throws {
        let id = dto.id
        let tripID = dto.tripID
        let trip = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == tripID }
        )).first

        guard let entity = try ctx.fetch(FetchDescriptor<ExpenseEntity>(
            predicate: #Predicate { $0.id == id }
        )).first else {
            ctx.insert(ExpenseEntity(
                id: dto.id,
                amount: dto.amount,
                currency: dto.currency,
                categoryID: dto.categoryID,
                descriptionText: dto.description,
                expenseDate: dto.expenseDate,
                receiptStoragePath: dto.receiptStoragePath,
                paymentMethodRaw: dto.paymentMethod,
                createdByID: dto.createdBy,
                lastEditedByID: dto.lastEditedBy,
                trip: trip,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                deletedAt: dto.deletedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
            return
        }

        // An expense never moves between trips; reattach a missing relationship
        // regardless of which side wins (heals partial pulls where the trips
        // table failed but expenses succeeded).
        if entity.trip == nil, let trip {
            entity.trip = trip
        }

        guard shouldApplyRemote(
            localUpdatedAt: entity.updatedAt, localDeletedAt: entity.deletedAt,
            localWriteID: entity.writeID, localPushedWriteID: entity.pushedWriteID,
            remoteUpdatedAt: dto.updatedAt, remoteDeletedAt: dto.deletedAt, remoteWriteID: dto.writeID
        ) else { return }
        entity.amount = dto.amount
        entity.currency = dto.currency
        entity.categoryID = dto.categoryID
        entity.descriptionText = dto.description
        entity.expenseDate = dto.expenseDate
        entity.receiptStoragePath = dto.receiptStoragePath
        entity.paymentMethodRaw = dto.paymentMethod
        entity.createdByID = dto.createdBy
        entity.lastEditedByID = dto.lastEditedBy
        entity.updatedAt = dto.updatedAt
        entity.deletedAt = dto.deletedAt
        entity.writeID = dto.writeID
        entity.pushedWriteID = dto.writeID
    }

    // MARK: - Expense payments

    static func apply(_ dto: ExpensePaymentDTO, in ctx: ModelContext) throws {
        let expenseID = dto.expenseID
        guard let expense = try ctx.fetch(FetchDescriptor<ExpenseEntity>(
            predicate: #Predicate { $0.id == expenseID }
        )).first else { return }

        guard let entity = expense.payments.first(where: { $0.tripPersonID == dto.tripPersonID }) else {
            ctx.insert(PaymentEntity(
                tripPersonID: dto.tripPersonID,
                amountPaid: dto.amountPaid,
                paymentModeRaw: dto.paymentMode,
                expense: expense,
                updatedAt: dto.updatedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
            return
        }
        guard shouldApplyRemote(
            localUpdatedAt: entity.updatedAt, localDeletedAt: nil,
            localWriteID: entity.writeID, localPushedWriteID: entity.pushedWriteID,
            remoteUpdatedAt: dto.updatedAt, remoteDeletedAt: nil, remoteWriteID: dto.writeID
        ) else { return }
        entity.amountPaid = dto.amountPaid
        entity.paymentModeRaw = dto.paymentMode
        entity.updatedAt = dto.updatedAt
        entity.writeID = dto.writeID
        entity.pushedWriteID = dto.writeID
    }

    // MARK: - Expense splits

    static func apply(_ dto: ExpenseSplitDTO, in ctx: ModelContext) throws {
        let expenseID = dto.expenseID
        guard let expense = try ctx.fetch(FetchDescriptor<ExpenseEntity>(
            predicate: #Predicate { $0.id == expenseID }
        )).first else { return }

        guard let entity = expense.splits.first(where: { $0.tripPersonID == dto.tripPersonID }) else {
            ctx.insert(ExpenseSplitEntity(
                tripPersonID: dto.tripPersonID,
                amountOwed: dto.amountOwed,
                splitTypeRaw: dto.splitType,
                shareUnits: dto.shareUnits,
                percentage: dto.percentage,
                expense: expense,
                updatedAt: dto.updatedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
            return
        }
        guard shouldApplyRemote(
            localUpdatedAt: entity.updatedAt, localDeletedAt: nil,
            localWriteID: entity.writeID, localPushedWriteID: entity.pushedWriteID,
            remoteUpdatedAt: dto.updatedAt, remoteDeletedAt: nil, remoteWriteID: dto.writeID
        ) else { return }
        entity.amountOwed = dto.amountOwed
        entity.splitTypeRaw = dto.splitType
        entity.shareUnits = dto.shareUnits
        entity.percentage = dto.percentage
        entity.updatedAt = dto.updatedAt
        entity.writeID = dto.writeID
        entity.pushedWriteID = dto.writeID
    }

    // MARK: - Settlements

    static func apply(_ dto: SettlementDTO, in ctx: ModelContext) throws {
        let id = dto.id
        let tripID = dto.tripID
        let trip = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == tripID }
        )).first

        guard let entity = try ctx.fetch(FetchDescriptor<SettlementEntity>(
            predicate: #Predicate { $0.id == id }
        )).first else {
            ctx.insert(SettlementEntity(
                id: dto.id,
                fromPersonID: dto.fromPersonID,
                toPersonID: dto.toPersonID,
                amount: dto.amount,
                currency: dto.currency,
                note: dto.note,
                settledAt: dto.settledAt,
                createdByID: dto.createdBy,
                trip: trip,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                deletedAt: dto.deletedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
            return
        }

        if entity.trip == nil, let trip {
            entity.trip = trip
        }

        guard shouldApplyRemote(
            localUpdatedAt: entity.updatedAt, localDeletedAt: entity.deletedAt,
            localWriteID: entity.writeID, localPushedWriteID: entity.pushedWriteID,
            remoteUpdatedAt: dto.updatedAt, remoteDeletedAt: dto.deletedAt, remoteWriteID: dto.writeID
        ) else { return }
        entity.fromPersonID = dto.fromPersonID
        entity.toPersonID = dto.toPersonID
        entity.amount = dto.amount
        entity.currency = dto.currency
        entity.note = dto.note
        entity.settledAt = dto.settledAt
        entity.createdByID = dto.createdBy
        entity.updatedAt = dto.updatedAt
        entity.deletedAt = dto.deletedAt
        entity.writeID = dto.writeID
        entity.pushedWriteID = dto.writeID
    }

    // MARK: - Trip mute prefs

    static func apply(_ dto: TripMuteDTO, in ctx: ModelContext) throws {
        let tripID = dto.tripID
        guard let entity = try ctx.fetch(FetchDescriptor<TripMuteEntity>(
            predicate: #Predicate { $0.tripID == tripID }
        )).first else {
            ctx.insert(TripMuteEntity(
                tripID: dto.tripID,
                isMuted: true,
                mutedAt: dto.mutedAt,
                updatedAt: dto.updatedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
            return
        }
        guard shouldApplyRemote(
            localUpdatedAt: entity.updatedAt, localDeletedAt: nil,
            localWriteID: entity.writeID, localPushedWriteID: entity.pushedWriteID,
            remoteUpdatedAt: dto.updatedAt, remoteDeletedAt: nil, remoteWriteID: dto.writeID
        ) else { return }
        entity.isMuted = true
        entity.mutedAt = dto.mutedAt
        entity.updatedAt = dto.updatedAt
        entity.writeID = dto.writeID
        entity.pushedWriteID = dto.writeID
    }
}
