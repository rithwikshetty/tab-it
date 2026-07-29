package com.rithwikshetty.tab.data.local

import androidx.room.Dao
import androidx.room.Embedded
import androidx.room.Query
import androidx.room.Relation
import androidx.room.Transaction
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

public data class ExpenseWithLedger(
    @Embedded
    public val expense: ExpenseEntity,
    @Relation(parentColumn = "id", entityColumn = "expense_id")
    public val payments: List<ExpensePaymentEntity>,
    @Relation(parentColumn = "id", entityColumn = "expense_id")
    public val splits: List<ExpenseSplitEntity>,
    @Relation(parentColumn = "id", entityColumn = "expense_id")
    public val receiptDraft: ReceiptDraftEntity?,
)

@Dao
public interface ProfileDao {
    @Upsert
    public suspend fun upsert(profile: ProfileEntity)

    @Upsert
    public suspend fun upsert(profiles: List<ProfileEntity>)

    @Query("SELECT * FROM profiles WHERE id = :id")
    public suspend fun find(id: String): ProfileEntity?

    @Query("SELECT * FROM profiles WHERE id = :id")
    public fun observe(id: String): Flow<ProfileEntity?>

    @Query(
        """
        UPDATE profiles
        SET activity_last_seen_at = :seenAt
        WHERE id = :id
        """,
    )
    public suspend fun updateActivityLastSeen(id: String, seenAt: String): Int
}

@Dao
public interface TripDao {
    @Upsert
    public suspend fun upsert(trip: TripEntity)

    @Upsert
    public suspend fun upsertTrips(trips: List<TripEntity>)

    @Upsert
    public suspend fun upsertPeople(people: List<TripPersonEntity>)

    @Upsert
    public suspend fun upsertCategories(categories: List<CategoryEntity>)

    @Query(
        """
        SELECT * FROM trips
        WHERE deleted_at IS NULL AND kind = 'trip'
        ORDER BY last_activity_at DESC, id ASC
        """,
    )
    public fun observeActiveTrips(): Flow<List<TripEntity>>

    @Query(
        """
        SELECT * FROM trips
        WHERE deleted_at IS NULL
        ORDER BY kind ASC, last_activity_at DESC, id ASC
        """,
    )
    public fun observeActiveContainers(): Flow<List<TripEntity>>

    @Query("SELECT * FROM trips WHERE id = :id")
    public suspend fun findTrip(id: String): TripEntity?

    @Query("SELECT * FROM trips WHERE id = :id")
    public fun observeTrip(id: String): Flow<TripEntity?>

    @Query(
        """
        SELECT * FROM trip_people
        WHERE trip_id = :tripId AND removed_at IS NULL AND deleted_at IS NULL
        ORDER BY display_name COLLATE NOCASE, id
        """,
    )
    public fun observeActivePeople(tripId: String): Flow<List<TripPersonEntity>>

    @Query(
        """
        SELECT * FROM trip_people
        WHERE removed_at IS NULL AND deleted_at IS NULL
        ORDER BY trip_id, display_name COLLATE NOCASE, id
        """,
    )
    public fun observeAllActivePeople(): Flow<List<TripPersonEntity>>

    @Query("SELECT * FROM trip_people WHERE id = :id")
    public suspend fun findPerson(id: String): TripPersonEntity?

    @Query(
        """
        SELECT * FROM trip_people
        WHERE trip_id = :tripId AND user_id = :userId
        LIMIT 1
        """,
    )
    public suspend fun findPersonForUser(tripId: String, userId: String): TripPersonEntity?

    @Query("SELECT * FROM categories WHERE id = :id")
    public suspend fun findCategory(id: String): CategoryEntity?

    @Query(
        """
        SELECT * FROM categories
        WHERE deleted_at IS NULL AND (trip_id IS NULL OR trip_id = :tripId)
        ORDER BY is_default DESC, name COLLATE NOCASE, id
        """,
    )
    public fun observeCategories(tripId: String): Flow<List<CategoryEntity>>

    @Query("SELECT COUNT(*) FROM trips")
    public suspend fun count(): Int

    @Query(
        """
        UPDATE trips
        SET name = :name, updated_at = :updatedAt, write_id = :writeId, is_dirty = 1
        WHERE id = :id AND deleted_at IS NULL
        """,
    )
    public suspend fun rename(id: String, name: String, updatedAt: String, writeId: String): Int

    @Query(
        """
        UPDATE trips
        SET deleted_at = :deletedAt, updated_at = :deletedAt, write_id = :writeId, is_dirty = 1
        WHERE id = :id AND deleted_at IS NULL
        """,
    )
    public suspend fun softDelete(id: String, deletedAt: String, writeId: String): Int

    @Query(
        """
        UPDATE trips
        SET is_dirty = 0
        WHERE id = :id AND write_id = :writeId
        """,
    )
    public suspend fun markClean(id: String, writeId: String): Int
}

@Dao
public interface ExpenseDao {
    @Upsert
    public suspend fun upsertExpense(expense: ExpenseEntity)

    @Upsert
    public suspend fun upsertPayments(payments: List<ExpensePaymentEntity>)

    @Upsert
    public suspend fun upsertSplits(splits: List<ExpenseSplitEntity>)

    @Upsert
    public suspend fun upsertReceiptDraft(receipt: ReceiptDraftEntity)

    @Query("DELETE FROM expense_payments WHERE expense_id = :expenseId")
    public suspend fun deletePayments(expenseId: String)

    @Query("DELETE FROM expense_splits WHERE expense_id = :expenseId")
    public suspend fun deleteSplits(expenseId: String)

    @Transaction
    @Query(
        """
        SELECT * FROM expenses
        WHERE trip_id = :tripId AND deleted_at IS NULL
        ORDER BY expense_date DESC, created_at DESC, id ASC
        """,
    )
    public fun observeActiveForTrip(tripId: String): Flow<List<ExpenseWithLedger>>

    @Transaction
    @Query(
        """
        SELECT * FROM expenses
        WHERE deleted_at IS NULL
        ORDER BY trip_id, expense_date DESC, created_at DESC, id ASC
        """,
    )
    public fun observeAllActive(): Flow<List<ExpenseWithLedger>>

    @Transaction
    @Query("SELECT * FROM expenses WHERE id = :id")
    public suspend fun findAggregate(id: String): ExpenseWithLedger?

    @Transaction
    @Query("SELECT * FROM expenses WHERE id = :id")
    public fun observeAggregate(id: String): Flow<ExpenseWithLedger?>

    @Query(
        """
        SELECT * FROM expense_payments
        WHERE expense_id = :expenseId AND trip_person_id = :personId
        """,
    )
    public suspend fun findPayment(expenseId: String, personId: String): ExpensePaymentEntity?

    @Query(
        """
        SELECT * FROM expense_splits
        WHERE expense_id = :expenseId AND trip_person_id = :personId
        """,
    )
    public suspend fun findSplit(expenseId: String, personId: String): ExpenseSplitEntity?

    @Query(
        """
        UPDATE expenses
        SET is_dirty = 0
        WHERE id = :id AND write_id = :writeId
        """,
    )
    public suspend fun markClean(id: String, writeId: String): Int

    @Query(
        """
        UPDATE expenses
        SET deleted_at = :deletedAt, updated_at = :deletedAt, write_id = :writeId, is_dirty = 1
        WHERE id = :id
        """,
    )
    public suspend fun softDelete(id: String, deletedAt: String, writeId: String): Int
}

@Dao
public interface SettlementDao {
    @Upsert
    public suspend fun upsert(settlement: SettlementEntity)

    @Query("SELECT * FROM settlements WHERE id = :id")
    public suspend fun find(id: String): SettlementEntity?

    @Query(
        """
        SELECT * FROM settlements
        WHERE trip_id = :tripId AND deleted_at IS NULL
        ORDER BY settled_at DESC, id ASC
        """,
    )
    public fun observeActiveForTrip(tripId: String): Flow<List<SettlementEntity>>

    @Query(
        """
        SELECT * FROM settlements
        WHERE deleted_at IS NULL
        ORDER BY trip_id, settled_at DESC, id ASC
        """,
    )
    public fun observeAllActive(): Flow<List<SettlementEntity>>

    @Query(
        """
        UPDATE settlements
        SET is_dirty = 0
        WHERE id = :id AND write_id = :writeId
        """,
    )
    public suspend fun markClean(id: String, writeId: String): Int

    @Query(
        """
        UPDATE settlements
        SET deleted_at = :deletedAt, updated_at = :deletedAt, write_id = :writeId, is_dirty = 1
        WHERE id = :id AND deleted_at IS NULL
        """,
    )
    public suspend fun softDelete(id: String, deletedAt: String, writeId: String): Int
}

@Dao
public interface ActivityDao {
    @Upsert
    public suspend fun upsert(items: List<ActivityEntity>)

    @Query("SELECT * FROM activity_log ORDER BY timestamp DESC, id ASC")
    public fun observeAll(): Flow<List<ActivityEntity>>
}

@Dao
public interface PreferenceDao {
    @Upsert
    public suspend fun upsert(mute: TripMutePreferenceEntity)

    @Query(
        """
        SELECT * FROM trip_mute_preferences
        WHERE trip_id = :tripId AND user_id = :userId
        """,
    )
    public suspend fun find(tripId: String, userId: String): TripMutePreferenceEntity?

    @Query("DELETE FROM trip_mute_preferences WHERE trip_id = :tripId AND user_id = :userId")
    public suspend fun deleteMute(tripId: String, userId: String)

    @Query(
        """
        UPDATE trip_mute_preferences
        SET is_dirty = 0
        WHERE trip_id = :tripId AND user_id = :userId AND write_id = :writeId
        """,
    )
    public suspend fun markClean(tripId: String, userId: String, writeId: String): Int

    @Query(
        """
        SELECT trip_id FROM trip_mute_preferences
        WHERE user_id = :userId AND deleted_at IS NULL
        ORDER BY trip_id
        """,
    )
    public fun observeMutedTripIds(userId: String): Flow<List<String>>
}

@Dao
public interface OutboxDao {
    @Upsert
    public suspend fun enqueue(item: OutboxEntity): Long

    @Query(
        """
        SELECT * FROM sync_outbox
        WHERE next_attempt_at IS NULL OR next_attempt_at <= :now
        ORDER BY sequence ASC
        LIMIT :limit
        """,
    )
    public suspend fun ready(now: String, limit: Int): List<OutboxEntity>

    @Query("SELECT * FROM sync_outbox ORDER BY sequence ASC")
    public fun observeAll(): Flow<List<OutboxEntity>>

    @Query("DELETE FROM sync_outbox WHERE sequence = :sequence")
    public suspend fun acknowledge(sequence: Long)

    @Query(
        """
        UPDATE sync_outbox
        SET attempt_count = attempt_count + 1, last_error = :message, next_attempt_at = :nextAttemptAt
        WHERE sequence = :sequence
        """,
    )
    public suspend fun markFailed(sequence: Long, message: String, nextAttemptAt: String)
}
