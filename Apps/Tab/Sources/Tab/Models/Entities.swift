import Foundation
import SwiftData

// MARK: - Profile

@Model
final class ProfileEntity {
    #Unique<ProfileEntity>([\.id])

    var id: UUID
    var displayName: String
    var avatarURL: String?
    /// Read cursor for the Activity feed. Unread = activity newer than this.
    var activityLastSeenAt: Date?
    var updatedAt: Date
    var writeID: UUID
    var pushedWriteID: UUID?

    init(
        id: UUID,
        displayName: String,
        avatarURL: String? = nil,
        activityLastSeenAt: Date? = nil,
        updatedAt: Date = .now,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.activityLastSeenAt = activityLastSeenAt
        self.updatedAt = updatedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - Trip

@Model
final class TripEntity {
    #Unique<TripEntity>([\.id])

    var id: UUID
    var name: String
    /// "trip" (a real, user-facing trip) or "non_group" (a hidden shadow group
    /// backing non-group expenses; never shown in the Trips list, server-managed).
    var kind: String = "trip"
    /// Canonical participant-set signature for non-group containers; nil for trips.
    var memberSignature: String?
    var createdByID: UUID
    var lastActivityAt: Date
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var writeID: UUID
    var pushedWriteID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \TripPersonEntity.trip)
    var people: [TripPersonEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \ExpenseEntity.trip)
    var expenses: [ExpenseEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \SettlementEntity.trip)
    var settlements: [SettlementEntity] = []

    var isNonGroup: Bool { kind == "non_group" }

    /// Current members: excludes soft-removed people. Use for member lists,
    /// avatar groups, and new-expense pickers. Removed people stay in `people`
    /// so their names keep resolving in history and balances.
    var activePeople: [TripPersonEntity] { people.filter { $0.removedAt == nil } }

    init(
        id: UUID = UUID(),
        name: String,
        kind: String = "trip",
        memberSignature: String? = nil,
        createdByID: UUID,
        lastActivityAt: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.memberSignature = memberSignature
        self.createdByID = createdByID
        self.lastActivityAt = lastActivityAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - TripPerson

@Model
final class TripPersonEntity {
    #Unique<TripPersonEntity>([\.id])

    var id: UUID
    var userID: UUID?
    var email: String
    var displayName: String
    var invitedByID: UUID?
    var joinedAt: Date?
    /// Membership state, not deletion: a removed person keeps their ledger
    /// rows and balances but drops out of member lists and pickers.
    var removedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var writeID: UUID
    var pushedWriteID: UUID?

    var trip: TripEntity?

    /// True for synthetic identities minted without a real address (Splitwise
    /// imports, email-less Apple accounts). Never show these to users.
    var hasPlaceholderEmail: Bool { email.hasSuffix("@users.tab") }

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        email: String,
        displayName: String,
        invitedByID: UUID? = nil,
        trip: TripEntity? = nil,
        joinedAt: Date? = nil,
        removedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = id
        self.userID = userID
        self.email = email
        self.displayName = displayName
        self.invitedByID = invitedByID
        self.trip = trip
        self.joinedAt = joinedAt
        self.removedAt = removedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - Category

@Model
final class CategoryEntity {
    #Unique<CategoryEntity>([\.id])

    var id: UUID
    var tripID: UUID?         // nil for built-in defaults
    var name: String
    var icon: String
    var isDefault: Bool
    var updatedAt: Date
    var deletedAt: Date?
    var writeID: UUID
    var pushedWriteID: UUID?

    init(
        id: UUID = UUID(),
        tripID: UUID? = nil,
        name: String,
        icon: String,
        isDefault: Bool,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = id
        self.tripID = tripID
        self.name = name
        self.icon = icon
        self.isDefault = isDefault
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - Expense

@Model
final class ExpenseEntity {
    #Unique<ExpenseEntity>([\.id])

    var id: UUID
    var amount: Decimal
    var currency: String
    var categoryID: UUID?
    var descriptionText: String
    var expenseDate: Date
    var receiptStoragePath: String?
    var paymentMethodRaw: String
    var createdByID: UUID
    var lastEditedByID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var writeID: UUID
    var pushedWriteID: UUID?

    var trip: TripEntity?

    @Relationship(deleteRule: .cascade, inverse: \PaymentEntity.expense)
    var payments: [PaymentEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \ExpenseSplitEntity.expense)
    var splits: [ExpenseSplitEntity] = []

    init(
        id: UUID = UUID(),
        amount: Decimal,
        currency: String,
        categoryID: UUID? = nil,
        descriptionText: String,
        expenseDate: Date,
        receiptStoragePath: String? = nil,
        paymentMethodRaw: String = "card",
        createdByID: UUID,
        lastEditedByID: UUID? = nil,
        trip: TripEntity? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.categoryID = categoryID
        self.descriptionText = descriptionText
        self.expenseDate = expenseDate
        self.receiptStoragePath = receiptStoragePath
        self.paymentMethodRaw = paymentMethodRaw
        self.createdByID = createdByID
        self.lastEditedByID = lastEditedByID
        self.trip = trip
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - Payment

@Model
final class PaymentEntity {
    #Unique<PaymentEntity>([\.id])

    var id: UUID
    var tripPersonID: UUID
    var amountPaid: Decimal
    var paymentModeRaw: String
    var updatedAt: Date
    var writeID: UUID
    var pushedWriteID: UUID?

    var expense: ExpenseEntity?

    init(
        tripPersonID: UUID,
        amountPaid: Decimal,
        paymentModeRaw: String,
        expense: ExpenseEntity? = nil,
        updatedAt: Date = .now,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = UUID()
        self.tripPersonID = tripPersonID
        self.amountPaid = amountPaid
        self.paymentModeRaw = paymentModeRaw
        self.expense = expense
        self.updatedAt = updatedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - ExpenseSplit

@Model
final class ExpenseSplitEntity {
    #Unique<ExpenseSplitEntity>([\.id])

    var id: UUID
    var tripPersonID: UUID
    var amountOwed: Decimal
    var splitTypeRaw: String
    /// Share weight when splitTypeRaw == "shares"; nil otherwise.
    var shareUnits: Decimal?
    /// Percentage of the total (0–100) when splitTypeRaw == "percentage"; nil otherwise.
    var percentage: Decimal?
    var updatedAt: Date
    var writeID: UUID
    var pushedWriteID: UUID?

    var expense: ExpenseEntity?

    init(
        tripPersonID: UUID,
        amountOwed: Decimal,
        splitTypeRaw: String,
        shareUnits: Decimal? = nil,
        percentage: Decimal? = nil,
        expense: ExpenseEntity? = nil,
        updatedAt: Date = .now,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = UUID()
        self.tripPersonID = tripPersonID
        self.amountOwed = amountOwed
        self.splitTypeRaw = splitTypeRaw
        self.shareUnits = shareUnits
        self.percentage = percentage
        self.expense = expense
        self.updatedAt = updatedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - Activity (notification feed)

/// One row per trip event, mirrored from the server-side `activity_log`.
/// Append-only and immutable: the client only ever inserts new rows on pull.
@Model
final class ActivityEntity {
    #Unique<ActivityEntity>([\.id])

    var id: UUID
    var tripID: UUID
    var actorID: UUID
    var action: String
    var entityType: String
    var entityID: UUID
    var timestamp: Date
    /// Device-local read marker. Never synced; pulls only insert new activity rows.
    var readAt: Date?
    /// Device-local dismissal (swipe-to-delete). The row is kept, not deleted,
    /// so the next pull can't re-insert it; the feed just stops showing it.
    var dismissedAt: Date?
    /// JSON-encoded `[String: String]` snapshot for offline rendering + push text.
    var snapshotData: Data?

    init(
        id: UUID,
        tripID: UUID,
        actorID: UUID,
        action: String,
        entityType: String,
        entityID: UUID,
        timestamp: Date,
        readAt: Date? = nil,
        dismissedAt: Date? = nil,
        snapshotData: Data? = nil
    ) {
        self.id = id
        self.tripID = tripID
        self.actorID = actorID
        self.action = action
        self.entityType = entityType
        self.entityID = entityID
        self.timestamp = timestamp
        self.readAt = readAt
        self.dismissedAt = dismissedAt
        self.snapshotData = snapshotData
    }

    var snapshot: [String: String] {
        guard let snapshotData,
              let dict = try? JSONDecoder().decode([String: String].self, from: snapshotData)
        else { return [:] }
        return dict
    }
}

// MARK: - Trip mute preference

/// Per-trip mute for the current user, mirroring `trip_mute_prefs`.
/// `isMuted == false` is a local tombstone awaiting an unmute push.
@Model
final class TripMuteEntity {
    #Unique<TripMuteEntity>([\.tripID])

    var tripID: UUID
    var isMuted: Bool
    var mutedAt: Date
    var updatedAt: Date
    var writeID: UUID
    var pushedWriteID: UUID?

    init(
        tripID: UUID,
        isMuted: Bool = true,
        mutedAt: Date = .now,
        updatedAt: Date = .now,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.tripID = tripID
        self.isMuted = isMuted
        self.mutedAt = mutedAt
        self.updatedAt = updatedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - Settlement

@Model
final class SettlementEntity {
    #Unique<SettlementEntity>([\.id])

    var id: UUID
    var fromPersonID: UUID
    var toPersonID: UUID
    var amount: Decimal
    var currency: String
    var note: String?
    var settledAt: Date
    var createdByID: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var writeID: UUID
    var pushedWriteID: UUID?

    var trip: TripEntity?

    init(
        id: UUID = UUID(),
        fromPersonID: UUID,
        toPersonID: UUID,
        amount: Decimal,
        currency: String,
        note: String? = nil,
        settledAt: Date,
        createdByID: UUID,
        trip: TripEntity? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = id
        self.fromPersonID = fromPersonID
        self.toPersonID = toPersonID
        self.amount = amount
        self.currency = currency
        self.note = note
        self.settledAt = settledAt
        self.createdByID = createdByID
        self.trip = trip
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}
