package com.rithwikshetty.tab.sync

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rithwikshetty.tab.data.LocalExpenseRepository
import com.rithwikshetty.tab.data.local.CategoryEntity
import com.rithwikshetty.tab.data.local.ExpenseWithLedger
import com.rithwikshetty.tab.data.local.ProfileEntity
import com.rithwikshetty.tab.data.local.SyncStamp
import com.rithwikshetty.tab.data.local.TabDatabase
import com.rithwikshetty.tab.data.local.TripEntity
import com.rithwikshetty.tab.data.local.TripPersonEntity
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.ExpenseSplit
import com.rithwikshetty.tab.domain.Money
import com.rithwikshetty.tab.domain.Payment
import com.rithwikshetty.tab.domain.PaymentMethod
import com.rithwikshetty.tab.domain.SplitType
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SyncEngineTest {
    private lateinit var database: TabDatabase

    @Before
    fun setUp() = runTest {
        database = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            TabDatabase::class.java,
        ).build()
        seedParents()
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun failedPushRetainsOutboxAndSchedulesRetryWithoutPullingOverDirtyData() = runTest {
        LocalExpenseRepository(database).save(expense())
        val remote = FakeGateway(
            pushFailure = IllegalStateException("offline"),
            pullFailure = IllegalStateException("offline"),
        )
        val report = SyncEngine(database, remote, FIXED_CLOCK).syncOnce()

        assertEquals(1, report.pushFailures)
        assertFalse(report.pullCompleted)
        val queued = database.outbox().observeAll().first().single()
        assertEquals(1, queued.attemptCount)
        assertEquals(NOW.plusSeconds(5).toString(), queued.nextAttemptAt)
        assertTrue(checkNotNull(database.expenses().findAggregate(EXPENSE_ID.toString())).expense.sync.isDirty)
    }

    @Test
    fun newerDirtyLocalRowWinsAgainstOlderRemoteSnapshot() = runTest {
        LocalExpenseRepository(database).save(expense())
        val local = checkNotNull(database.expenses().findAggregate(EXPENSE_ID.toString()))
        val olderRemote = RemoteExpenseLedger(
            expense = local.expense.copy(
                description = "Older remote",
                sync = SyncStamp(
                    NOW.minusSeconds(30).toString(),
                    null,
                    UUID.randomUUID().toString(),
                    false,
                ),
            ),
            payments = local.payments,
            splits = local.splits,
        )

        RemoteSnapshotApplier(database).apply(emptySnapshot(expenses = listOf(olderRemote)))

        val preserved = checkNotNull(database.expenses().findAggregate(EXPENSE_ID.toString()))
        assertEquals("Offline expense", preserved.expense.description)
        assertTrue(preserved.expense.sync.isDirty)
    }

    @Test
    fun remoteTombstoneWinsAgainstLiveDirtyLocalRow() = runTest {
        LocalExpenseRepository(database).save(expense())
        val local = checkNotNull(database.expenses().findAggregate(EXPENSE_ID.toString()))
        val remoteDelete = RemoteExpenseLedger(
            expense = local.expense.copy(
                sync = SyncStamp(
                    NOW.minusSeconds(30).toString(),
                    NOW.minusSeconds(30).toString(),
                    UUID.randomUUID().toString(),
                    false,
                ),
            ),
            payments = emptyList(),
            splits = emptyList(),
        )

        RemoteSnapshotApplier(database).apply(emptySnapshot(expenses = listOf(remoteDelete)))

        val deleted = checkNotNull(database.expenses().findAggregate(EXPENSE_ID.toString()))
        assertEquals(NOW.minusSeconds(30).toString(), deleted.expense.sync.deletedAt)
        assertFalse(deleted.expense.sync.isDirty)
    }

    private suspend fun seedParents() {
        val clean = SyncStamp(NOW.toString(), null, UUID.randomUUID().toString(), false)
        database.profiles().upsert(ProfileEntity(USER_ID.toString(), "Local User", null, null, NOW.toString(), clean))
        database.trips().upsert(
            TripEntity(
                TRIP_ID.toString(),
                "Offline trip",
                "trip",
                null,
                USER_ID.toString(),
                NOW.toString(),
                NOW.toString(),
                clean,
            ),
        )
        database.trips().upsertPeople(
            listOf(
                TripPersonEntity(
                    PERSON_ID.toString(),
                    TRIP_ID.toString(),
                    USER_ID.toString(),
                    "local@tab.local",
                    "Local User",
                    USER_ID.toString(),
                    NOW.toString(),
                    null,
                    NOW.toString(),
                    clean,
                ),
            ),
        )
        database.trips().upsertCategories(
            listOf(
                CategoryEntity(
                    CATEGORY_ID.toString(),
                    null,
                    "Food & Drink",
                    "bowl-food",
                    true,
                    NOW.toString(),
                    clean,
                ),
            ),
        )
    }

    private fun expense(): Expense = Expense(
        id = EXPENSE_ID,
        tripId = TRIP_ID,
        amount = Money.parse("8.40", "GBP"),
        categoryId = CATEGORY_ID,
        description = "Offline expense",
        receiptStoragePath = null,
        paymentMethod = PaymentMethod.CASH,
        expenseDate = NOW,
        payments = listOf(Payment(PERSON_ID, BigDecimal("8.40"), SplitType.EXACT)),
        splits = listOf(ExpenseSplit(PERSON_ID, BigDecimal("8.40"), SplitType.EXACT)),
        createdBy = USER_ID,
        createdAt = NOW,
        updatedAt = NOW,
        deletedAt = null,
    )

    private companion object {
        val NOW: Instant = Instant.parse("2026-07-29T12:00:00Z")
        val FIXED_CLOCK: Clock = Clock.fixed(NOW, ZoneOffset.UTC)
        val USER_ID: UUID = UUID.fromString("11111111-1111-1111-1111-111111111111")
        val TRIP_ID: UUID = UUID.fromString("22222222-2222-2222-2222-222222222222")
        val PERSON_ID: UUID = UUID.fromString("33333333-3333-3333-3333-333333333333")
        val CATEGORY_ID: UUID = UUID.fromString("00000001-0000-0000-0000-000000000000")
        val EXPENSE_ID: UUID = UUID.fromString("44444444-4444-4444-4444-444444444444")
    }
}

private class FakeGateway(
    private val snapshot: RemoteSnapshot = emptySnapshot(),
    private val pushFailure: Exception? = null,
    private val pullFailure: Exception? = null,
) : RemoteGateway {
    override suspend fun restoreSession(): AuthenticatedUser? = currentUser()

    override suspend fun signIn(email: String, password: String): AuthenticatedUser =
        AuthenticatedUser("11111111-1111-1111-1111-111111111111", email)

    override suspend fun signOut() = Unit

    override suspend fun close() = Unit

    override fun currentUser(): AuthenticatedUser =
        AuthenticatedUser("11111111-1111-1111-1111-111111111111", "local@tab.local")

    override suspend fun pullSnapshot(): RemoteSnapshot {
        pullFailure?.let { throw it }
        return snapshot
    }

    override suspend fun pushExpense(expense: ExpenseWithLedger): PushReceipt {
        pushFailure?.let { throw it }
        return PushReceipt(expense.expense.sync.writeId)
    }

    override suspend fun pushTrip(
        trip: com.rithwikshetty.tab.data.local.TripEntity,
        creator: com.rithwikshetty.tab.data.local.TripPersonEntity?,
    ): PushReceipt = PushReceipt(trip.sync.writeId)

    override suspend fun addTripPerson(
        tripId: String,
        email: String,
        displayName: String?,
        personId: String,
    ) = Unit

    override suspend fun removeTripPerson(personId: String) = Unit

    override fun observeCurrentTripChanges(tripId: String): Flow<Unit> = emptyFlow()
}

private fun emptySnapshot(
    expenses: List<RemoteExpenseLedger> = emptyList(),
): RemoteSnapshot = RemoteSnapshot(
    profiles = emptyList(),
    trips = emptyList(),
    people = emptyList(),
    categories = emptyList(),
    expenses = expenses,
    settlements = emptyList(),
    activity = emptyList(),
    mutePreferences = emptyList(),
)
