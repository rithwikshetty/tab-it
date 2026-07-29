package com.rithwikshetty.tab.ui.activity

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.rithwikshetty.tab.data.LocalActivity
import com.rithwikshetty.tab.data.LocalActivityState
import com.rithwikshetty.tab.data.LocalTripSummary
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

data class ActivityUiItem(
    val activity: LocalActivity,
    val isUnread: Boolean,
)

data class ActivityUiState(
    val items: List<ActivityUiItem> = emptyList(),
    val unreadCount: Int = 0,
    val mutedTripIds: Set<UUID> = emptySet(),
)

object ActivityPresenter {
    fun present(state: LocalActivityState, currentUserId: UUID): ActivityUiState {
        val items = state.items.map { item ->
            val unread = item.actorId != currentUserId &&
                item.tripId !in state.mutedTripIds &&
                (state.lastSeenAt == null || item.timestamp > state.lastSeenAt)
            ActivityUiItem(item, unread)
        }
        return ActivityUiState(
            items,
            items.count(ActivityUiItem::isUnread),
            state.mutedTripIds,
        )
    }
}

@Composable
fun ActivityScreen(
    state: ActivityUiState,
    trips: List<LocalTripSummary>,
    isWorking: Boolean,
    onRefresh: () -> Unit,
    onOpenTrip: (UUID) -> Unit,
    modifier: Modifier = Modifier,
) {
    val tripNames = trips.associate { it.id to it.name }
    Column(modifier = modifier.fillMaxSize()) {
        Text(
            text = "Activity",
            modifier = Modifier
                .padding(horizontal = 24.dp, vertical = 20.dp)
                .semantics { heading() },
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
        )
        if (state.items.isEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .clickable(enabled = !isWorking, onClick = onRefresh)
                    .padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(Icons.Outlined.NotificationsNone, contentDescription = null)
                Text(
                    text = "No activity yet",
                    modifier = Modifier.padding(top = 12.dp),
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(
                    text = "Changes from your trips will appear here. Tap to refresh.",
                    modifier = Modifier.padding(top = 6.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(state.items, key = { it.activity.id }) { item ->
                    val activity = item.activity
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onOpenTrip(activity.tripId) }
                            .padding(horizontal = 20.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Text(
                            text = if (item.isUnread) "New" else "",
                            modifier = Modifier.padding(end = 12.dp),
                            color = MaterialTheme.colorScheme.primary,
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = activity.title(),
                                fontWeight = if (item.isUnread) {
                                    FontWeight.SemiBold
                                } else {
                                    FontWeight.Normal
                                },
                            )
                            Text(
                                text = tripNames[activity.tripId] ?: "Trip",
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodySmall,
                            )
                            Text(
                                text = activity.timestamp.atZone(ZoneId.systemDefault())
                                    .format(activityDateFormatter),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun LocalActivity.title(): String {
    val noun = when (entityType) {
        "expense" -> "expense"
        "settlement" -> "settlement"
        "trip_person" -> "trip member"
        "trip" -> "trip"
        else -> "item"
    }
    val verb = when {
        action.endsWith("_created") || action.endsWith("_joined") -> "added"
        action.endsWith("_updated") -> "updated"
        action.endsWith("_deleted") || action.endsWith("_removed") -> "removed"
        else -> action.replace('_', ' ')
    }
    return "${noun.replaceFirstChar(Char::uppercase)} $verb"
}

private val activityDateFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("d MMM, HH:mm")
