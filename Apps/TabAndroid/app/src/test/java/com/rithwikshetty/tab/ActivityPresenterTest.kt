package com.rithwikshetty.tab

import com.rithwikshetty.tab.data.LocalActivity
import com.rithwikshetty.tab.data.LocalActivityState
import com.rithwikshetty.tab.ui.activity.ActivityPresenter
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivityPresenterTest {
    @Test
    fun unreadExcludesOwnMutedAndPreviouslySeenChanges() {
        val current = UUID.randomUUID()
        val other = UUID.randomUUID()
        val mutedTrip = UUID.randomUUID()
        val activeTrip = UUID.randomUUID()
        val seen = Instant.parse("2026-07-29T12:00:00Z")
        val state = ActivityPresenter.present(
            LocalActivityState(
                items = listOf(
                    activity(activeTrip, current, seen.plusSeconds(30)),
                    activity(mutedTrip, other, seen.plusSeconds(20)),
                    activity(activeTrip, other, seen.minusSeconds(10)),
                    activity(activeTrip, other, seen.plusSeconds(10)),
                ),
                mutedTripIds = setOf(mutedTrip),
                lastSeenAt = seen,
            ),
            current,
        )

        assertEquals(1, state.unreadCount)
        assertFalse(state.items[0].isUnread)
        assertFalse(state.items[1].isUnread)
        assertFalse(state.items[2].isUnread)
        assertTrue(state.items[3].isUnread)
    }

    private fun activity(tripId: UUID, actorId: UUID, at: Instant): LocalActivity =
        LocalActivity(
            id = UUID.randomUUID(),
            tripId = tripId,
            actorId = actorId,
            action = "expense_created",
            entityType = "expense",
            entityId = UUID.randomUUID(),
            timestamp = at,
            snapshotJson = null,
        )
}
