package com.rithwikshetty.tab.data.local

import androidx.room.ColumnInfo
import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

public data class SyncStamp(
    @ColumnInfo(name = "updated_at")
    public val updatedAt: String,
    @ColumnInfo(name = "deleted_at")
    public val deletedAt: String?,
    @ColumnInfo(name = "write_id")
    public val writeId: String,
    @ColumnInfo(name = "is_dirty")
    public val isDirty: Boolean,
)

@Entity(tableName = "profiles")
public data class ProfileEntity(
    @PrimaryKey
    public val id: String,
    @ColumnInfo(name = "display_name")
    public val displayName: String,
    @ColumnInfo(name = "avatar_url")
    public val avatarUrl: String?,
    @ColumnInfo(name = "activity_last_seen_at")
    public val activityLastSeenAt: String?,
    @ColumnInfo(name = "created_at")
    public val createdAt: String,
    @Embedded
    public val sync: SyncStamp,
)

@Entity(
    tableName = "trips",
    foreignKeys = [
        ForeignKey(
            entity = ProfileEntity::class,
            parentColumns = ["id"],
            childColumns = ["created_by"],
            onDelete = ForeignKey.RESTRICT,
        ),
    ],
    indices = [
        Index(value = ["created_by"]),
        Index(value = ["last_activity_at"]),
        Index(value = ["member_signature"], unique = true),
    ],
)
public data class TripEntity(
    @PrimaryKey
    public val id: String,
    public val name: String,
    public val kind: String,
    @ColumnInfo(name = "member_signature")
    public val memberSignature: String?,
    @ColumnInfo(name = "created_by")
    public val createdBy: String,
    @ColumnInfo(name = "last_activity_at")
    public val lastActivityAt: String,
    @ColumnInfo(name = "created_at")
    public val createdAt: String,
    @Embedded
    public val sync: SyncStamp,
)

@Entity(
    tableName = "trip_people",
    primaryKeys = ["id"],
    foreignKeys = [
        ForeignKey(
            entity = TripEntity::class,
            parentColumns = ["id"],
            childColumns = ["trip_id"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index(value = ["trip_id", "email"], unique = true),
        Index(value = ["trip_id", "user_id"], unique = true),
        Index(value = ["user_id"]),
    ],
)
public data class TripPersonEntity(
    public val id: String,
    @ColumnInfo(name = "trip_id")
    public val tripId: String,
    @ColumnInfo(name = "user_id")
    public val userId: String?,
    public val email: String,
    @ColumnInfo(name = "display_name")
    public val displayName: String,
    @ColumnInfo(name = "invited_by")
    public val invitedBy: String?,
    @ColumnInfo(name = "joined_at")
    public val joinedAt: String?,
    @ColumnInfo(name = "removed_at")
    public val removedAt: String?,
    @ColumnInfo(name = "created_at")
    public val createdAt: String,
    @Embedded
    public val sync: SyncStamp,
)

@Entity(
    tableName = "categories",
    foreignKeys = [
        ForeignKey(
            entity = TripEntity::class,
            parentColumns = ["id"],
            childColumns = ["trip_id"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index(value = ["trip_id"])],
)
public data class CategoryEntity(
    @PrimaryKey
    public val id: String,
    @ColumnInfo(name = "trip_id")
    public val tripId: String?,
    public val name: String,
    public val icon: String,
    @ColumnInfo(name = "is_default")
    public val isDefault: Boolean,
    @ColumnInfo(name = "created_at")
    public val createdAt: String,
    @Embedded
    public val sync: SyncStamp,
)

@Entity(
    tableName = "expenses",
    foreignKeys = [
        ForeignKey(
            entity = TripEntity::class,
            parentColumns = ["id"],
            childColumns = ["trip_id"],
            onDelete = ForeignKey.RESTRICT,
        ),
        ForeignKey(
            entity = CategoryEntity::class,
            parentColumns = ["id"],
            childColumns = ["category_id"],
            onDelete = ForeignKey.SET_NULL,
        ),
        ForeignKey(
            entity = ProfileEntity::class,
            parentColumns = ["id"],
            childColumns = ["created_by"],
            onDelete = ForeignKey.RESTRICT,
        ),
    ],
    indices = [
        Index(value = ["trip_id", "expense_date"]),
        Index(value = ["category_id"]),
        Index(value = ["created_by"]),
    ],
)
public data class ExpenseEntity(
    @PrimaryKey
    public val id: String,
    @ColumnInfo(name = "trip_id")
    public val tripId: String,
    @ColumnInfo(name = "amount_text")
    public val amountText: String,
    public val currency: String,
    @ColumnInfo(name = "category_id")
    public val categoryId: String?,
    public val description: String,
    @ColumnInfo(name = "expense_date")
    public val expenseDate: String,
    @ColumnInfo(name = "receipt_storage_path")
    public val receiptStoragePath: String?,
    @ColumnInfo(name = "payment_method")
    public val paymentMethod: String,
    @ColumnInfo(name = "created_by")
    public val createdBy: String,
    @ColumnInfo(name = "last_edited_by")
    public val lastEditedBy: String?,
    @ColumnInfo(name = "created_at")
    public val createdAt: String,
    @Embedded
    public val sync: SyncStamp,
)

@Entity(
    tableName = "expense_payments",
    primaryKeys = ["expense_id", "trip_person_id"],
    foreignKeys = [
        ForeignKey(
            entity = ExpenseEntity::class,
            parentColumns = ["id"],
            childColumns = ["expense_id"],
            onDelete = ForeignKey.CASCADE,
        ),
        ForeignKey(
            entity = TripPersonEntity::class,
            parentColumns = ["id"],
            childColumns = ["trip_person_id"],
            onDelete = ForeignKey.RESTRICT,
        ),
    ],
    indices = [Index(value = ["trip_person_id"])],
)
public data class ExpensePaymentEntity(
    @ColumnInfo(name = "expense_id")
    public val expenseId: String,
    @ColumnInfo(name = "trip_person_id")
    public val tripPersonId: String,
    @ColumnInfo(name = "amount_paid_text")
    public val amountPaidText: String,
    @ColumnInfo(name = "payment_mode")
    public val paymentMode: String,
    @ColumnInfo(name = "created_at")
    public val createdAt: String,
    @Embedded
    public val sync: SyncStamp,
)

@Entity(
    tableName = "expense_splits",
    primaryKeys = ["expense_id", "trip_person_id"],
    foreignKeys = [
        ForeignKey(
            entity = ExpenseEntity::class,
            parentColumns = ["id"],
            childColumns = ["expense_id"],
            onDelete = ForeignKey.CASCADE,
        ),
        ForeignKey(
            entity = TripPersonEntity::class,
            parentColumns = ["id"],
            childColumns = ["trip_person_id"],
            onDelete = ForeignKey.RESTRICT,
        ),
    ],
    indices = [Index(value = ["trip_person_id"])],
)
public data class ExpenseSplitEntity(
    @ColumnInfo(name = "expense_id")
    public val expenseId: String,
    @ColumnInfo(name = "trip_person_id")
    public val tripPersonId: String,
    @ColumnInfo(name = "amount_owed_text")
    public val amountOwedText: String,
    @ColumnInfo(name = "split_type")
    public val splitType: String,
    @ColumnInfo(name = "share_units_text")
    public val shareUnitsText: String?,
    @ColumnInfo(name = "percentage_text")
    public val percentageText: String?,
    @ColumnInfo(name = "created_at")
    public val createdAt: String,
    @Embedded
    public val sync: SyncStamp,
)

@Entity(
    tableName = "settlements",
    foreignKeys = [
        ForeignKey(
            entity = TripEntity::class,
            parentColumns = ["id"],
            childColumns = ["trip_id"],
            onDelete = ForeignKey.RESTRICT,
        ),
        ForeignKey(
            entity = TripPersonEntity::class,
            parentColumns = ["id"],
            childColumns = ["from_person_id"],
            onDelete = ForeignKey.RESTRICT,
        ),
        ForeignKey(
            entity = TripPersonEntity::class,
            parentColumns = ["id"],
            childColumns = ["to_person_id"],
            onDelete = ForeignKey.RESTRICT,
        ),
    ],
    indices = [
        Index(value = ["trip_id", "settled_at"]),
        Index(value = ["from_person_id"]),
        Index(value = ["to_person_id"]),
    ],
)
public data class SettlementEntity(
    @PrimaryKey
    public val id: String,
    @ColumnInfo(name = "trip_id")
    public val tripId: String,
    @ColumnInfo(name = "from_person_id")
    public val fromPersonId: String,
    @ColumnInfo(name = "to_person_id")
    public val toPersonId: String,
    @ColumnInfo(name = "amount_text")
    public val amountText: String,
    public val currency: String,
    public val note: String?,
    @ColumnInfo(name = "settled_at")
    public val settledAt: String,
    @ColumnInfo(name = "created_by")
    public val createdBy: String,
    @ColumnInfo(name = "created_at")
    public val createdAt: String,
    @Embedded
    public val sync: SyncStamp,
)

@Entity(
    tableName = "activity_log",
    indices = [
        Index(value = ["trip_id", "timestamp"]),
        Index(value = ["entity_type", "entity_id"]),
    ],
)
public data class ActivityEntity(
    @PrimaryKey
    public val id: String,
    @ColumnInfo(name = "trip_id")
    public val tripId: String,
    @ColumnInfo(name = "actor_id")
    public val actorId: String,
    public val action: String,
    @ColumnInfo(name = "entity_type")
    public val entityType: String,
    @ColumnInfo(name = "entity_id")
    public val entityId: String,
    public val timestamp: String,
    @ColumnInfo(name = "snapshot_json")
    public val snapshotJson: String?,
)

@Entity(
    tableName = "trip_mute_preferences",
    primaryKeys = ["trip_id", "user_id"],
    foreignKeys = [
        ForeignKey(
            entity = TripEntity::class,
            parentColumns = ["id"],
            childColumns = ["trip_id"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index(value = ["user_id"])],
)
public data class TripMutePreferenceEntity(
    @ColumnInfo(name = "trip_id")
    public val tripId: String,
    @ColumnInfo(name = "user_id")
    public val userId: String,
    @ColumnInfo(name = "muted_at")
    public val mutedAt: String,
    @Embedded
    public val sync: SyncStamp,
)

@Entity(
    tableName = "receipt_drafts",
    foreignKeys = [
        ForeignKey(
            entity = ExpenseEntity::class,
            parentColumns = ["id"],
            childColumns = ["expense_id"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index(value = ["upload_state"])],
)
public data class ReceiptDraftEntity(
    @PrimaryKey
    @ColumnInfo(name = "expense_id")
    public val expenseId: String,
    @ColumnInfo(name = "local_uri")
    public val localUri: String,
    @ColumnInfo(name = "remote_path")
    public val remotePath: String?,
    @ColumnInfo(name = "upload_state")
    public val uploadState: String,
    @ColumnInfo(name = "updated_at")
    public val updatedAt: String,
)

@Entity(
    tableName = "sync_outbox",
    indices = [
        Index(value = ["entity_type", "entity_id", "write_id"], unique = true),
        Index(value = ["next_attempt_at", "sequence"]),
    ],
)
public data class OutboxEntity(
    @PrimaryKey(autoGenerate = true)
    public val sequence: Long = 0,
    @ColumnInfo(name = "entity_type")
    public val entityType: String,
    @ColumnInfo(name = "entity_id")
    public val entityId: String,
    public val operation: String,
    @ColumnInfo(name = "write_id")
    public val writeId: String,
    @ColumnInfo(name = "created_at")
    public val createdAt: String,
    @ColumnInfo(name = "attempt_count")
    public val attemptCount: Int = 0,
    @ColumnInfo(name = "last_error")
    public val lastError: String? = null,
    @ColumnInfo(name = "next_attempt_at")
    public val nextAttemptAt: String? = null,
)
