package com.rithwikshetty.tab.sync

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rithwikshetty.tab.data.LocalExpenseRepository
import com.rithwikshetty.tab.data.LocalTripRepository
import com.rithwikshetty.tab.data.local.TabDatabase
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.ExpenseSplit
import com.rithwikshetty.tab.domain.Money
import com.rithwikshetty.tab.domain.Payment
import com.rithwikshetty.tab.domain.PaymentMethod
import com.rithwikshetty.tab.domain.SplitType
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LocalSupabaseIntegrationTest {
    private lateinit var database: TabDatabase
    private lateinit var gateway: SupabaseRemoteGateway

    @Before
    fun setUp() {
        database = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            TabDatabase::class.java,
        ).build()
        gateway = SupabaseRemoteGateway.create(
            checkNotNull(LocalBackendConfiguration.debugOrNull()) {
                "Run supabase/scripts/configure_android_local.sh before integration tests."
            },
        )
    }

    @After
    fun tearDown() = runBlocking {
        runCatching { gateway.signOut() }
        database.close()
    }

    @Test
    fun localSignInAndPullHydrateRoom() = runBlocking {
        assertNull(gateway.currentUser())
        val user = gateway.signIn(LOCAL_EMAIL, LOCAL_PASSWORD)
        assertEquals(USER_ID.toString(), user.id)

        val snapshot = gateway.pullSnapshot()
        assertTrue(snapshot.trips.any { it.id == TRIP_ID.toString() })
        assertTrue(
            snapshot.expenses.map { it.expense.id }.containsAll(SEEDED_EXPENSE_IDS),
        )

        val applied = RemoteSnapshotApplier(database).apply(snapshot)
        assertTrue(applied > 0)
        assertEquals("Lake District", LocalTripRepository(database).observeTrips().first().single().name)
        assertTrue(
            LocalExpenseRepository(database).observeExpenses(TRIP_ID).first()
                .map { it.id.toString() }
                .containsAll(SEEDED_EXPENSE_IDS),
        )
    }

    @Test
    fun outboxPushIsConfirmedPulledAndAcknowledged() = runBlocking {
        gateway.signIn(LOCAL_EMAIL, LOCAL_PASSWORD)
        RemoteSnapshotApplier(database).apply(gateway.pullSnapshot())
        val repository = LocalExpenseRepository(database)
        val expenseId = UUID.randomUUID()
        val now = Instant.now()
        val expense = Expense(
            id = expenseId,
            tripId = TRIP_ID,
            amount = Money.parse("12.34", "GBP"),
            categoryId = UUID.fromString("00000001-0000-0000-0000-000000000000"),
            description = "Android local sync test",
            receiptStoragePath = null,
            paymentMethod = PaymentMethod.CARD,
            expenseDate = now,
            payments = listOf(Payment(SELF_PERSON_ID, BigDecimal("12.34"), SplitType.EXACT)),
            splits = listOf(ExpenseSplit(SELF_PERSON_ID, BigDecimal("12.34"), SplitType.EXACT)),
            createdBy = USER_ID,
            createdAt = now,
            updatedAt = now,
            deletedAt = null,
        )
        repository.save(expense)

        val report = SyncEngine(database, gateway).syncOnce()

        assertEquals(1, report.pushed)
        assertTrue(report.pullCompleted)
        assertTrue(database.outbox().observeAll().first().isEmpty())
        assertFalse(checkNotNull(database.expenses().findAggregate(expenseId.toString())).expense.sync.isDirty)
        assertNotNull(
            gateway.pullSnapshot().expenses.singleOrNull { it.expense.id == expenseId.toString() },
        )
    }

    @Test
    fun realtimeEmitsOnlyForTheSelectedTripChannel() = runBlocking {
        gateway.signIn(LOCAL_EMAIL, LOCAL_PASSWORD)
        RemoteSnapshotApplier(database).apply(gateway.pullSnapshot())
        val expenseId = UUID.randomUUID()
        val now = Instant.now()
        LocalExpenseRepository(database).save(testExpense(expenseId, now))
        val aggregate = checkNotNull(database.expenses().findAggregate(expenseId.toString()))

        val event = async {
            withTimeout(20_000) {
                gateway.observeCurrentTripChanges(TRIP_ID.toString()).first()
            }
        }
        delay(1_000)
        gateway.pushExpense(aggregate)

        event.await()
    }

    private fun testExpense(id: UUID, now: Instant): Expense = Expense(
        id = id,
        tripId = TRIP_ID,
        amount = Money.parse("3.21", "GBP"),
        categoryId = UUID.fromString("00000001-0000-0000-0000-000000000000"),
        description = "Android realtime test",
        receiptStoragePath = null,
        paymentMethod = PaymentMethod.CARD,
        expenseDate = now,
        payments = listOf(Payment(SELF_PERSON_ID, BigDecimal("3.21"), SplitType.EXACT)),
        splits = listOf(ExpenseSplit(SELF_PERSON_ID, BigDecimal("3.21"), SplitType.EXACT)),
        createdBy = USER_ID,
        createdAt = now,
        updatedAt = now,
        deletedAt = null,
    )

    private companion object {
        const val LOCAL_EMAIL: String = "mock@tab.local"
        const val LOCAL_PASSWORD: String = "local-only-password"
        val USER_ID: UUID = UUID.fromString("11111111-1111-1111-1111-111111111111")
        val TRIP_ID: UUID = UUID.fromString("44444444-4444-4444-4444-444444444444")
        val SELF_PERSON_ID: UUID = UUID.fromString("61111111-1111-1111-1111-111111111111")
        val SEEDED_EXPENSE_IDS: Set<String> = setOf(
            "81111111-1111-1111-1111-111111111111",
            "82222222-2222-2222-2222-222222222222",
            "83333333-3333-3333-3333-333333333333",
        )
    }
}
