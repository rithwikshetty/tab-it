package com.rithwikshetty.tab.ui.friends

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import com.rithwikshetty.tab.sync.RemoteParticipant
import java.math.BigDecimal

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FriendsScreen(
    state: FriendsUiState,
    isWorking: Boolean,
    onRefresh: () -> Unit,
    onAddExpense: () -> Unit,
    onOpenFriend: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Friends",
                        modifier = Modifier.semantics { heading() },
                        fontWeight = FontWeight.SemiBold,
                    )
                },
                actions = {
                    IconButton(onClick = onRefresh, enabled = !isWorking) {
                        Icon(Icons.Outlined.Refresh, contentDescription = "Refresh friends")
                    }
                },
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = onAddExpense,
                modifier = Modifier.testTag("addFriendExpense"),
                icon = { Icon(Icons.Outlined.Add, contentDescription = null) },
                text = { Text("Add expense") },
            )
        },
    ) { contentPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (state.overall.isNotEmpty()) {
                item {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text(
                                text = "Overall",
                                modifier = Modifier.semantics { heading() },
                                fontWeight = FontWeight.SemiBold,
                            )
                            state.overall.forEach { line ->
                                val parts = buildList {
                                    if (line.youOwe > BigDecimal.ZERO) {
                                        add(
                                            "You owe ${line.youOwe.toPlainString()} " +
                                                line.currency,
                                        )
                                    }
                                    if (line.youAreOwed > BigDecimal.ZERO) {
                                        add(
                                            "you are owed ${line.youAreOwed.toPlainString()} " +
                                                line.currency,
                                        )
                                    }
                                }
                                Text(
                                    text = parts.joinToString(" · "),
                                    modifier = Modifier.padding(top = 5.dp),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
            if (state.active.isEmpty() && state.settled.isEmpty()) {
                item {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 72.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Icon(
                            Icons.Outlined.Groups,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            text = "No friends yet",
                            modifier = Modifier.padding(top = 12.dp),
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = "Add an expense or start a trip to see who you owe.",
                            modifier = Modifier.padding(top = 5.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            } else {
                if (state.active.isNotEmpty()) {
                    item { SectionTitle("People") }
                    items(state.active, key = { it.identity.canonicalKey }) { friend ->
                        FriendCard(friend, onClick = { onOpenFriend(friend.identity.canonicalKey) })
                    }
                }
                if (state.settled.isNotEmpty()) {
                    item { SectionTitle("Settled up") }
                    items(state.settled, key = { it.identity.canonicalKey }) { friend ->
                        FriendCard(friend, onClick = { onOpenFriend(friend.identity.canonicalKey) })
                    }
                }
            }
            item { Spacer(modifier = Modifier.height(88.dp)) }
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text = text,
        modifier = Modifier.semantics { heading() },
        style = MaterialTheme.typography.titleLarge,
        fontWeight = FontWeight.SemiBold,
    )
}

@Composable
private fun FriendCard(friend: FriendRow, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(friend.displayName, fontWeight = FontWeight.SemiBold)
                Text(
                    text = if (friend.isPending) "Invite pending" else friend.sourceSummary,
                    modifier = Modifier.padding(top = 2.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                if (friend.isSettled) {
                    Text(
                        text = "all settled",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    friend.lines.forEach { line ->
                        Text(
                            text = if (line.amount > BigDecimal.ZERO) {
                                "${line.amount.toPlainString()} ${line.currency} owes you"
                            } else {
                                "${line.amount.abs().toPlainString()} ${line.currency} you owe"
                            },
                            fontWeight = FontWeight.SemiBold,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FriendDetailScreen(
    detail: FriendDetail?,
    onBack: () -> Unit,
    onSettle: (FriendSourceRow) -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(detail?.friend?.displayName ?: "Friend") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { contentPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (detail == null) {
                item {
                    Text(
                        text = "This person is no longer available.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                item {
                    Text(
                        text = if (detail.friend.isPending) {
                            "Invite pending"
                        } else {
                            detail.friend.sourceSummary
                        },
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (detail.friend.lines.isEmpty()) {
                    item {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Text(
                                text = "You are all settled.",
                                modifier = Modifier.padding(16.dp),
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                    }
                } else {
                    item { SectionTitle("Overall balance") }
                    items(detail.friend.lines, key = { it.currency }) { line ->
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Text(
                                text = if (line.amount > BigDecimal.ZERO) {
                                    "${detail.friend.displayName} owes you " +
                                        "${line.amount.toPlainString()} ${line.currency}"
                                } else {
                                    "You owe ${detail.friend.displayName} " +
                                        "${line.amount.abs().toPlainString()} ${line.currency}"
                                },
                                modifier = Modifier.padding(16.dp),
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                    }
                    item { SectionTitle("By source") }
                    items(
                        detail.sources,
                        key = { "${it.containerId}-${it.currency}" },
                    ) { source ->
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(source.sourceName, fontWeight = FontWeight.SemiBold)
                                    Text(
                                        text = if (source.amount > BigDecimal.ZERO) {
                                            "owes you ${source.amount.toPlainString()} " +
                                                source.currency
                                        } else {
                                            "you owe ${source.amount.abs().toPlainString()} " +
                                                source.currency
                                        },
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                TextButton(onClick = { onSettle(source) }) {
                                    Text("Settle")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NonGroupExpensePickerScreen(
    knownPeople: List<FriendRow>,
    isWorking: Boolean,
    onBack: () -> Unit,
    onResolve: (List<RemoteParticipant>) -> Unit,
    modifier: Modifier = Modifier,
) {
    val selected = remember { mutableStateListOf<RemoteParticipant>() }
    var email by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    fun addTypedPerson() {
        val normalized = email.trim().lowercase()
        error = when {
            !normalized.contains("@") -> "Enter a valid email address."
            selected.any { it.email == normalized } -> "That person is already selected."
            else -> null
        }
        if (error == null) {
            selected += RemoteParticipant(
                email = normalized,
                displayName = displayName.trim().ifEmpty {
                    normalized.substringBefore("@").replaceFirstChar(Char::uppercase)
                },
            )
            email = ""
            displayName = ""
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("New friend expense") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(
                        onClick = { onResolve(selected.toList()) },
                        enabled = selected.isNotEmpty() && !isWorking,
                        modifier = Modifier.testTag("resolveFriendExpense"),
                    ) {
                        Text("Next")
                    }
                },
            )
        },
    ) { contentPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Text(
                    text = "Who is involved?",
                    modifier = Modifier.semantics { heading() },
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "Tab uses a private non-group ledger shared by exactly these people.",
                    modifier = Modifier.padding(top = 4.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (knownPeople.isNotEmpty()) {
                item { SectionTitle("People you split with") }
                items(knownPeople, key = { it.identity.canonicalKey }) { friend ->
                    val friendEmail = friend.email
                    if (friendEmail != null) {
                        val checked = selected.any { it.email == friendEmail }
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    if (checked) {
                                        selected.removeAll { it.email == friendEmail }
                                    } else {
                                        selected += RemoteParticipant(
                                            friendEmail,
                                            friend.displayName,
                                        )
                                    }
                                },
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Checkbox(
                                    checked = checked,
                                    onCheckedChange = null,
                                )
                                Column(modifier = Modifier.padding(start = 8.dp)) {
                                    Text(friend.displayName, fontWeight = FontWeight.SemiBold)
                                    Text(
                                        friendEmail,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                }
                            }
                        }
                    }
                }
            }
            item { SectionTitle("Invite by email") }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (error != null) {
                        Text(checkNotNull(error), color = MaterialTheme.colorScheme.error)
                    }
                    OutlinedTextField(
                        value = email,
                        onValueChange = { email = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("friendEmail"),
                        label = { Text("Email") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    )
                    OutlinedTextField(
                        value = displayName,
                        onValueChange = { displayName = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Name (optional)") },
                        singleLine = true,
                    )
                    TextButton(
                        onClick = ::addTypedPerson,
                        enabled = email.isNotBlank(),
                    ) {
                        Text("Add person")
                    }
                }
            }
            if (selected.isNotEmpty()) {
                item { SectionTitle("Selected") }
                items(selected, key = RemoteParticipant::email) { person ->
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(person.displayName, fontWeight = FontWeight.SemiBold)
                                Text(
                                    person.email,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            TextButton(
                                onClick = { selected.removeAll { it.email == person.email } },
                            ) {
                                Text("Remove")
                            }
                        }
                    }
                }
            }
        }
    }
}
