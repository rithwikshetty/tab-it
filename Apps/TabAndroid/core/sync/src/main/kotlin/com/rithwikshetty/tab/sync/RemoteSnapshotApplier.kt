package com.rithwikshetty.tab.sync

import androidx.room.withTransaction
import com.rithwikshetty.tab.data.local.SyncStamp
import com.rithwikshetty.tab.data.local.TabDatabase
import com.rithwikshetty.tab.domain.ConflictResolver
import com.rithwikshetty.tab.domain.MergeDecision
import com.rithwikshetty.tab.domain.Versioned
import java.time.Instant
import java.util.UUID

public class RemoteSnapshotApplier(
    private val database: TabDatabase,
) {
    public suspend fun apply(snapshot: RemoteSnapshot): Int = database.withTransaction {
        var applied = 0

        snapshot.profiles.forEach { remote ->
            val local = database.profiles().find(remote.id)
            if (shouldApply(local?.sync, remote.sync)) {
                database.profiles().upsert(
                    remote.copy(activityLastSeenAt = remote.activityLastSeenAt ?: local?.activityLastSeenAt),
                )
                applied += 1
            }
        }
        snapshot.trips.forEach { remote ->
            if (shouldApply(database.trips().findTrip(remote.id)?.sync, remote.sync)) {
                database.trips().upsert(remote)
                applied += 1
            }
        }
        snapshot.people.forEach { remote ->
            if (shouldApply(database.trips().findPerson(remote.id)?.sync, remote.sync)) {
                database.trips().upsertPeople(listOf(remote))
                applied += 1
            }
        }
        snapshot.categories.forEach { remote ->
            if (shouldApply(database.trips().findCategory(remote.id)?.sync, remote.sync)) {
                database.trips().upsertCategories(listOf(remote))
                applied += 1
            }
        }
        snapshot.expenses.forEach { remote ->
            val local = database.expenses().findAggregate(remote.expense.id)
            if (shouldApply(local?.expense?.sync, remote.expense.sync)) {
                database.expenses().upsertExpense(remote.expense)
                database.expenses().deletePayments(remote.expense.id)
                database.expenses().deleteSplits(remote.expense.id)
                database.expenses().upsertPayments(remote.payments)
                database.expenses().upsertSplits(remote.splits)
                applied += 1 + remote.payments.size + remote.splits.size
            }
        }
        snapshot.settlements.forEach { remote ->
            if (shouldApply(database.settlements().find(remote.id)?.sync, remote.sync)) {
                database.settlements().upsert(remote)
                applied += 1
            }
        }
        if (snapshot.activity.isNotEmpty()) {
            database.activity().upsert(snapshot.activity)
            applied += snapshot.activity.size
        }
        snapshot.mutePreferences.forEach { remote ->
            val local = database.preferences().find(remote.tripId, remote.userId)
            if (shouldApply(local?.sync, remote.sync)) {
                database.preferences().upsert(remote)
                applied += 1
            }
        }

        applied
    }

    internal fun shouldApply(local: SyncStamp?, remote: SyncStamp): Boolean {
        if (local == null) return true
        return ConflictResolver.merge(
            local = local.versioned(),
            localIsDirty = local.isDirty,
            remote = remote.versioned(),
        ) == MergeDecision.APPLY_REMOTE
    }
}

private fun SyncStamp.versioned(): Versioned<Unit> = Versioned(
    value = Unit,
    updatedAt = Instant.parse(updatedAt),
    deletedAt = deletedAt?.let(Instant::parse),
    writeId = UUID.fromString(writeId),
)
