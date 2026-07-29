package com.rithwikshetty.tab.data

import androidx.room.withTransaction
import com.rithwikshetty.tab.data.local.CategoryEntity
import com.rithwikshetty.tab.data.local.ExpenseEntity
import com.rithwikshetty.tab.data.local.ExpensePaymentEntity
import com.rithwikshetty.tab.data.local.ExpenseSplitEntity
import com.rithwikshetty.tab.data.local.ProfileEntity
import com.rithwikshetty.tab.data.local.SyncStamp
import com.rithwikshetty.tab.data.local.TabDatabase
import com.rithwikshetty.tab.data.local.TripEntity
import com.rithwikshetty.tab.data.local.TripPersonEntity
import java.time.Instant
import java.util.UUID

public object DebugSeedData {
    public val currentUserId: UUID = UUID.fromString("11111111-1111-1111-1111-111111111111")
    public val tripId: UUID = UUID.fromString("22222222-2222-2222-2222-222222222222")
    public val currentPersonId: UUID = UUID.fromString("33333333-3333-3333-3333-333333333331")
    public val friendPersonId: UUID = UUID.fromString("33333333-3333-3333-3333-333333333332")
    public val expenseId: UUID = UUID.fromString("55555555-5555-5555-5555-555555555555")

    public suspend fun seedIfEmpty(database: TabDatabase) {
        if (database.trips().count() != 0) return
        val now = Instant.parse("2026-07-29T12:00:00Z").toString()
        val clean = SyncStamp(now, null, UUID.fromString("44444444-4444-4444-4444-444444444444").toString(), false)
        database.withTransaction {
            database.profiles().upsert(
                ProfileEntity(
                    id = currentUserId.toString(),
                    displayName = "Test User",
                    avatarUrl = null,
                    activityLastSeenAt = null,
                    createdAt = now,
                    sync = clean,
                ),
            )
            database.trips().upsert(
                TripEntity(
                    id = tripId.toString(),
                    name = "Local Test Trip",
                    kind = "trip",
                    memberSignature = null,
                    createdBy = currentUserId.toString(),
                    lastActivityAt = now,
                    createdAt = now,
                    sync = clean,
                ),
            )
            database.trips().upsertPeople(
                listOf(
                    TripPersonEntity(
                        id = currentPersonId.toString(),
                        tripId = tripId.toString(),
                        userId = currentUserId.toString(),
                        email = "mock@tab.local",
                        displayName = "Test User",
                        invitedBy = currentUserId.toString(),
                        joinedAt = now,
                        removedAt = null,
                        createdAt = now,
                        sync = clean,
                    ),
                    TripPersonEntity(
                        id = friendPersonId.toString(),
                        tripId = tripId.toString(),
                        userId = null,
                        email = "friend@tab.local",
                        displayName = "Local Friend",
                        invitedBy = currentUserId.toString(),
                        joinedAt = null,
                        removedAt = null,
                        createdAt = now,
                        sync = clean,
                    ),
                ),
            )
            database.trips().upsertCategories(
                listOf(
                    CategoryEntity(
                        id = "00000001-0000-0000-0000-000000000000",
                        tripId = null,
                        name = "Food & Drink",
                        icon = "bowl-food",
                        isDefault = true,
                        createdAt = now,
                        sync = clean,
                    ),
                ),
            )
            database.expenses().upsertExpense(
                ExpenseEntity(
                    id = expenseId.toString(),
                    tripId = tripId.toString(),
                    amountText = "48.00",
                    currency = "GBP",
                    categoryId = "00000001-0000-0000-0000-000000000000",
                    description = "Local test dinner",
                    expenseDate = "2026-07-29",
                    receiptStoragePath = null,
                    paymentMethod = "card",
                    createdBy = currentUserId.toString(),
                    lastEditedBy = null,
                    createdAt = now,
                    sync = clean,
                ),
            )
            database.expenses().upsertPayments(
                listOf(
                    ExpensePaymentEntity(
                        expenseId.toString(),
                        currentPersonId.toString(),
                        "48.00",
                        "exact",
                        now,
                        clean,
                    ),
                ),
            )
            database.expenses().upsertSplits(
                listOf(
                    ExpenseSplitEntity(
                        expenseId.toString(),
                        currentPersonId.toString(),
                        "24.00",
                        "equal",
                        null,
                        null,
                        now,
                        clean,
                    ),
                    ExpenseSplitEntity(
                        expenseId.toString(),
                        friendPersonId.toString(),
                        "24.00",
                        "equal",
                        null,
                        null,
                        now,
                        clean,
                    ),
                ),
            )
        }
    }
}
