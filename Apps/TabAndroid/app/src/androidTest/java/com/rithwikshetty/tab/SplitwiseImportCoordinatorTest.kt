package com.rithwikshetty.tab

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rithwikshetty.tab.domain.SplitwiseImport
import com.rithwikshetty.tab.sync.AuthenticatedUser
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SplitwiseImportCoordinatorTest {
    private lateinit var container: TabContainer
    private var importedTripId: UUID? = null

    @Before
    fun setUp() = runBlocking {
        container = TabContainer(
            ApplicationProvider.getApplicationContext(),
            databaseName = "splitwise-import-test.db",
            persistBackendSession = false,
        )
        container.tripRepository.clearAccountData()
        val remote = checkNotNull(container.remoteGateway)
        remote.signIn(LOCAL_EMAIL, LOCAL_PASSWORD)
        val report = checkNotNull(container.syncEngine).syncOnce()
        check(report.pullCompleted && report.pushFailures == 0)
    }

    @After
    fun tearDown() = runBlocking {
        importedTripId?.let { tripId ->
            runCatching {
                container.tripRepository.archive(tripId)
                checkNotNull(container.syncEngine).syncOnce()
            }
        }
        runCatching { checkNotNull(container.remoteGateway).signOut() }
        container.tripRepository.clearAccountData()
    }

    @Test
    fun parsedPreviewImportsExpenseSettlementAndPeopleThroughLocalBackend() = runBlocking {
        val parsed = SplitwiseImport.parse(
            """
            Date,Description,Category,Cost,Currency,Alice,Bob
            2026-07-01,"Dinner, drinks",Food and drink,10.00,GBP,5.00,-5.00
            2026-07-02,Repayment,Payment,3.00,GBP,3.00,-3.00
            """.trimIndent(),
        )
        val user = AuthenticatedUser(USER_ID.toString(), LOCAL_EMAIL)

        val tripId = container.splitwiseImporter.run(
            parsed,
            "Imported local trip",
            "Alice",
            user,
        )
        importedTripId = tripId

        val people = container.tripRepository.observePeople(tripId).first()
        assertEquals(setOf("Sam", "Bob"), people.map { it.displayName }.toSet())
        assertEquals("Dinner, drinks", container.expenseRepository.observeExpenses(tripId).first().single().description)
        assertEquals("Repayment", container.settlementRepository.observeSettlements(tripId).first().single().note)
        assertTrue(
            checkNotNull(container.remoteGateway).pullSnapshot().trips.any {
                it.id == tripId.toString()
            },
        )
    }

    private companion object {
        const val LOCAL_EMAIL: String = "sam@tab.local"
        const val LOCAL_PASSWORD: String = "local-only-password"
        val USER_ID: UUID = UUID.fromString("33333333-3333-3333-3333-333333333333")
    }
}
