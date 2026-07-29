package com.rithwikshetty.tab.data

import android.database.sqlite.SQLiteConstraintException
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rithwikshetty.tab.data.local.CategoryEntity
import com.rithwikshetty.tab.data.local.ActivityEntity
import com.rithwikshetty.tab.data.local.OutboxEntity
import com.rithwikshetty.tab.data.local.ProfileEntity
import com.rithwikshetty.tab.data.local.SyncStamp
import com.rithwikshetty.tab.data.local.TabDatabase
import com.rithwikshetty.tab.data.local.SettlementEntity
import com.rithwikshetty.tab.data.local.TripMutePreferenceEntity
import com.rithwikshetty.tab.data.local.TripEntity
import com.rithwikshetty.tab.data.local.TripPersonEntity
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.ExpenseSplit
import com.rithwikshetty.tab.domain.Money
import com.rithwikshetty.tab.domain.Payment
import com.rithwikshetty.tab.domain.SplitType
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LocalDatabaseTest {
    private lateinit var database: TabDatabase
    private lateinit var repository: LocalExpenseRepository

    private val userId = UUID.fromString("11111111-1111-1111-1111-111111111111")
    private val tripId = UUID.fromString("22222222-2222-2222-2222-222222222222")
    private val payerId = UUID.fromString("33333333-3333-3333-3333-333333333331")
    private val debtorId = UUID.fromString("33333333-3333-3333-3333-333333333332")
    private val now = Instant.parse("2026-07-29T12:00:00Z")

    @Before
    fun setUp() = runTest {
        database = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            TabDatabase::class.java,
        ).build()
        repository = LocalExpenseRepository(database)
        seedLedgerParents()
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun expenseLedgerAndReceiptPersistAtomicallyWithExactDecimals() = runTest {
        val expense = expense()
        repository.save(expense, receiptLocalUri = "content://tab/receipt-1")

        val stored = repository.observeExpenses(tripId).first().single()
        assertEquals(0, stored.amount.amount.compareTo(BigDecimal("10.00")))
        assertEquals(expense.payments, stored.payments)
        assertEquals(expense.splits, stored.splits)
        assertNotNull(database.expenses().findAggregate(expense.id.toString())?.receiptDraft)

        val outbox = database.outbox().observeAll().first()
        assertEquals(1, outbox.size)
        assertEquals("upsert", outbox.single().operation)
        assertEquals(expense.id.toString(), outbox.single().entityId)
    }

    @Test
    fun failedChildConstraintRollsBackExpenseLedgerAndOutbox() = runTest {
        val missingPerson = UUID.fromString("99999999-9999-9999-9999-999999999999")
        val invalid = expense().copy(
            splits = listOf(ExpenseSplit(missingPerson, BigDecimal("10.00"), SplitType.EXACT)),
        )

        assertThrows(SQLiteConstraintException::class.java) {
            kotlinx.coroutines.runBlocking { repository.save(invalid) }
        }
        assertNull(database.expenses().findAggregate(invalid.id.toString()))
        assertTrue(database.outbox().observeAll().first().isEmpty())
    }

    @Test
    fun softDeleteDisappearsFromActiveFlowAndQueuesDelete() = runTest {
        val expense = expense()
        repository.save(expense)
        repository.softDelete(expense.id, now.plusSeconds(60))

        assertTrue(repository.observeExpenses(tripId).first().isEmpty())
        val aggregate = database.expenses().findAggregate(expense.id.toString())
        assertNotNull(aggregate?.expense?.sync?.deletedAt)
        assertEquals(listOf("upsert", "delete"), database.outbox().observeAll().first().map { it.operation })
    }

    @Test
    fun outboxIsStrictlyOrderedAndRespectsRetryTime() = runTest {
        database.outbox().enqueue(outbox("first", now.toString()))
        val delayed = database.outbox().enqueue(outbox("second", now.plusSeconds(1).toString()))
        database.outbox().markFailed(delayed, "offline", now.plusSeconds(300).toString())
        database.outbox().enqueue(outbox("third", now.plusSeconds(2).toString()))

        assertEquals(
            listOf("first", "third"),
            database.outbox().ready(now.plusSeconds(10).toString(), 10).map { it.entityId },
        )
        assertEquals(
            listOf("first", "second", "third"),
            database.outbox().observeAll().first().map { it.entityId },
        )
    }

    @Test
    fun activeTripAndPeopleFlowsExcludeSoftDeletedOrRemovedRows() = runTest {
        val tripRepository = LocalTripRepository(database)
        assertEquals(listOf("Local Test Trip"), tripRepository.observeTrips().first().map { it.name })
        assertEquals(2, database.trips().observeActivePeople(tripId.toString()).first().size)

        val removed = database.trips().findPerson(debtorId.toString())!!.copy(removedAt = now.toString())
        database.trips().upsertPeople(listOf(removed))
        assertEquals(1, database.trips().observeActivePeople(tripId.toString()).first().size)
    }

    @Test
    fun repositoryRejectsInvalidTotalsBeforeOpeningTransaction() = runTest {
        val invalid = expense().copy(
            payments = listOf(Payment(payerId, BigDecimal("9.99"), SplitType.EXACT)),
        )
        assertThrows(IllegalArgumentException::class.java) {
            kotlinx.coroutines.runBlocking { repository.save(invalid) }
        }
        assertNull(database.expenses().findAggregate(invalid.id.toString()))
    }

    @Test
    fun debugSeedIsFictionalIdempotentAndDoesNotQueueRemoteWork() = runTest {
        val isolated = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            TabDatabase::class.java,
        ).build()
        try {
            DebugSeedData.seedIfEmpty(isolated)
            DebugSeedData.seedIfEmpty(isolated)
            assertEquals(1, isolated.trips().count())
            assertEquals(1, LocalExpenseRepository(isolated).observeExpenses(DebugSeedData.tripId).first().size)
            assertTrue(isolated.outbox().observeAll().first().isEmpty())
        } finally {
            isolated.close()
        }
    }

    @Test
    fun settlementActivityAndMuteStoresRemainObservableOffline() = runTest {
        val clean = SyncStamp(now.toString(), null, UUID.randomUUID().toString(), false)
        database.settlements().upsert(
            SettlementEntity(
                id = UUID.randomUUID().toString(),
                tripId = tripId.toString(),
                fromPersonId = debtorId.toString(),
                toPersonId = payerId.toString(),
                amountText = "6.00",
                currency = "GBP",
                note = "Cash",
                settledAt = now.toString(),
                createdBy = userId.toString(),
                createdAt = now.toString(),
                sync = clean,
            ),
        )
        database.activity().upsert(
            listOf(
                ActivityEntity(
                    id = UUID.randomUUID().toString(),
                    tripId = tripId.toString(),
                    actorId = userId.toString(),
                    action = "settlement_created",
                    entityType = "settlement",
                    entityId = UUID.randomUUID().toString(),
                    timestamp = now.toString(),
                    snapshotJson = """{"amount":"6.00","currency":"GBP"}""",
                ),
            ),
        )
        database.preferences().upsert(
            TripMutePreferenceEntity(
                tripId.toString(),
                userId.toString(),
                now.toString(),
                clean,
            ),
        )

        assertEquals("6.00", database.settlements().observeActiveForTrip(tripId.toString()).first().single().amountText)
        assertEquals("settlement_created", database.activity().observeAll().first().single().action)
        assertEquals(
            listOf(tripId.toString()),
            database.preferences().observeMutedTripIds(userId.toString()).first(),
        )

        database.preferences().deleteMute(tripId.toString(), userId.toString())
        assertTrue(database.preferences().observeMutedTripIds(userId.toString()).first().isEmpty())
    }

    private suspend fun seedLedgerParents() {
        val clean = SyncStamp(now.toString(), null, UUID.randomUUID().toString(), false)
        database.profiles().upsert(
            ProfileEntity(
                userId.toString(),
                "Test User",
                null,
                null,
                now.toString(),
                clean,
            ),
        )
        database.trips().upsert(
            TripEntity(
                tripId.toString(),
                "Local Test Trip",
                "trip",
                null,
                userId.toString(),
                now.toString(),
                now.toString(),
                clean,
            ),
        )
        database.trips().upsertPeople(
            listOf(
                person(payerId, "Test User", "mock@tab.local", userId, clean),
                person(debtorId, "Local Friend", "friend@tab.local", null, clean),
            ),
        )
        database.trips().upsertCategories(
            listOf(
                CategoryEntity(
                    "00000001-0000-0000-0000-000000000000",
                    null,
                    "Food & Drink",
                    "bowl-food",
                    true,
                    now.toString(),
                    clean,
                ),
            ),
        )
    }

    private fun person(
        id: UUID,
        name: String,
        email: String,
        linkedUser: UUID?,
        sync: SyncStamp,
    ): TripPersonEntity = TripPersonEntity(
        id.toString(),
        tripId.toString(),
        linkedUser?.toString(),
        email,
        name,
        userId.toString(),
        linkedUser?.let { now.toString() },
        null,
        now.toString(),
        sync,
    )

    private fun expense(): Expense = Expense(
        id = UUID.fromString("55555555-5555-5555-5555-555555555555"),
        tripId = tripId,
        amount = Money.parse("10.00", "GBP"),
        categoryId = UUID.fromString("00000001-0000-0000-0000-000000000000"),
        description = "Local dinner",
        expenseDate = now,
        payments = listOf(Payment(payerId, BigDecimal("10.00"), SplitType.EXACT)),
        splits = listOf(
            ExpenseSplit(payerId, BigDecimal("4.00"), SplitType.EXACT),
            ExpenseSplit(debtorId, BigDecimal("6.00"), SplitType.EXACT),
        ),
        createdBy = userId,
        createdAt = now,
        updatedAt = now,
    )

    private fun outbox(id: String, createdAt: String): OutboxEntity = OutboxEntity(
        entityType = "expense",
        entityId = id,
        operation = "upsert",
        writeId = UUID.randomUUID().toString(),
        createdAt = createdAt,
    )
}
