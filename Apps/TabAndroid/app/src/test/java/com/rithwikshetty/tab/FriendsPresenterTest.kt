package com.rithwikshetty.tab

import com.rithwikshetty.tab.data.LocalContainer
import com.rithwikshetty.tab.data.LocalLedgerSnapshot
import com.rithwikshetty.tab.data.LocalPerson
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.ExpenseSplit
import com.rithwikshetty.tab.domain.Money
import com.rithwikshetty.tab.domain.Payment
import com.rithwikshetty.tab.domain.SplitType
import com.rithwikshetty.tab.ui.friends.FriendsPresenter
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class FriendsPresenterTest {
    @Test
    fun aggregatesCurrentUsersBalancesAndKeepsSettledFriends() {
        val snapshot = LocalLedgerSnapshot(
            containers = listOf(
                LocalContainer(TRIP_ID, "Lake District", "trip", null),
                LocalContainer(NON_GROUP_ID, "", "non_group", "friend@tab.local|mock@tab.local"),
            ),
            people = listOf(
                person(SELF_TRIP_PERSON, USER_ID, "mock@tab.local", "Test User", TRIP_ID),
                person(FRIEND_TRIP_PERSON, FRIEND_ID, "friend@tab.local", "Local Friend", TRIP_ID),
                person(SELF_NON_GROUP_PERSON, USER_ID, "mock@tab.local", "Test User", NON_GROUP_ID),
                person(
                    FRIEND_NON_GROUP_PERSON,
                    FRIEND_ID,
                    "friend@tab.local",
                    "Local Friend",
                    NON_GROUP_ID,
                ),
                person(
                    SETTLED_PERSON,
                    null,
                    "pending@tab.local",
                    "Pending Friend",
                    TRIP_ID,
                ),
            ),
            expenses = listOf(expense()),
        )

        val state = FriendsPresenter.present(snapshot, USER_ID)

        assertEquals(1, state.overall.size)
        assertEquals(0, state.overall.single().youAreOwed.compareTo(BigDecimal("6.00")))
        assertEquals("Local Friend", state.active.single().displayName)
        assertEquals("Non-group + Lake District", state.active.single().sourceSummary)
        assertEquals(0, state.active.single().lines.single().amount.compareTo(BigDecimal("6.00")))
        assertEquals("Pending Friend", state.settled.single().displayName)
        assertFalse(state.knownPeople.isEmpty())
        val detail = state.details.getValue(state.active.single().identity.canonicalKey)
        assertEquals("Lake District", detail.sources.single().sourceName)
        assertEquals(FRIEND_TRIP_PERSON, detail.sources.single().suggestion.fromUser)
        assertEquals(SELF_TRIP_PERSON, detail.sources.single().suggestion.toUser)
    }

    private fun expense(): Expense = Expense(
        id = UUID.randomUUID(),
        tripId = TRIP_ID,
        amount = Money.parse("10.00", "GBP"),
        description = "Dinner",
        expenseDate = NOW,
        payments = listOf(Payment(SELF_TRIP_PERSON, BigDecimal("10.00"), SplitType.EXACT)),
        splits = listOf(
            ExpenseSplit(SELF_TRIP_PERSON, BigDecimal("4.00"), SplitType.EXACT),
            ExpenseSplit(FRIEND_TRIP_PERSON, BigDecimal("6.00"), SplitType.EXACT),
        ),
        createdBy = USER_ID,
        createdAt = NOW,
        updatedAt = NOW,
    )

    private fun person(
        id: UUID,
        userId: UUID?,
        email: String,
        name: String,
        tripId: UUID,
    ): LocalPerson = LocalPerson(
        id = id,
        userId = userId,
        email = email,
        displayName = name,
        hasJoined = userId != null,
        tripId = tripId,
    )

    private companion object {
        val NOW: Instant = Instant.parse("2026-07-29T12:00:00Z")
        val USER_ID: UUID = UUID.fromString("11111111-1111-1111-1111-111111111111")
        val FRIEND_ID: UUID = UUID.fromString("22222222-2222-2222-2222-222222222222")
        val TRIP_ID: UUID = UUID.fromString("33333333-3333-3333-3333-333333333333")
        val NON_GROUP_ID: UUID = UUID.fromString("44444444-4444-4444-4444-444444444444")
        val SELF_TRIP_PERSON: UUID = UUID.fromString("51111111-1111-1111-1111-111111111111")
        val FRIEND_TRIP_PERSON: UUID = UUID.fromString("52222222-2222-2222-2222-222222222222")
        val SELF_NON_GROUP_PERSON: UUID = UUID.fromString("53333333-3333-3333-3333-333333333333")
        val FRIEND_NON_GROUP_PERSON: UUID =
            UUID.fromString("54444444-4444-4444-4444-444444444444")
        val SETTLED_PERSON: UUID = UUID.fromString("55555555-5555-5555-5555-555555555555")
    }
}
