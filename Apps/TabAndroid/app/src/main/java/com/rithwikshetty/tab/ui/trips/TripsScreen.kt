package com.rithwikshetty.tab.ui.trips

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Luggage
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.rithwikshetty.tab.data.LocalTripSummary
import com.rithwikshetty.tab.data.LocalPerson
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.Settlement
import com.rithwikshetty.tab.domain.SimplifiedDebt
import com.rithwikshetty.tab.ui.app.TripContentUiState
import java.math.BigDecimal
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TripsScreen(
    trips: List<LocalTripSummary>,
    isWorking: Boolean,
    onRefresh: () -> Unit,
    onCreate: (String) -> Unit,
    onOpenTrip: (UUID) -> Unit,
    modifier: Modifier = Modifier,
) {
    var showCreate by remember { mutableStateOf(false) }
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Trips",
                        modifier = Modifier.semantics { heading() },
                        fontWeight = FontWeight.SemiBold,
                    )
                },
                actions = {
                    IconButton(
                        onClick = onRefresh,
                        enabled = !isWorking,
                    ) {
                        Icon(Icons.Outlined.Refresh, contentDescription = "Refresh trips")
                    }
                },
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { showCreate = true },
                icon = { Icon(Icons.Outlined.Add, contentDescription = null) },
                text = { Text("New trip") },
            )
        },
    ) { contentPadding ->
        PullToRefreshBox(
            isRefreshing = isWorking,
            onRefresh = onRefresh,
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding),
        ) {
            if (trips.isEmpty()) {
                EmptyTrips(modifier = Modifier.fillMaxSize())
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    item { Spacer(modifier = Modifier.height(4.dp)) }
                    items(trips, key = { it.id }) { trip ->
                        TripRow(
                            trip = trip,
                            onClick = { onOpenTrip(trip.id) },
                            modifier = Modifier.padding(horizontal = 16.dp),
                        )
                    }
                    item { Spacer(modifier = Modifier.height(88.dp)) }
                }
            }
        }
    }

    if (showCreate) {
        TripNameDialog(
            title = "New trip",
            action = "Create",
            initialName = "",
            onDismiss = { showCreate = false },
            onConfirm = {
                showCreate = false
                onCreate(it)
            },
        )
    }
}

@Composable
private fun EmptyTrips(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = Icons.Outlined.Luggage,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = "No trips yet",
            modifier = Modifier.padding(top = 16.dp),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "Create a trip to start sharing expenses.",
            modifier = Modifier.padding(top = 6.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

@Composable
private fun TripRow(
    trip: LocalTripSummary,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = trip.name,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = "Updated ${trip.lastActivityAt.atZone(ZoneId.systemDefault()).format(tripDateFormatter)}",
                    modifier = Modifier.padding(top = 4.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TripDetailScreen(
    trip: LocalTripSummary?,
    content: TripContentUiState,
    currentUserId: UUID,
    isMuted: Boolean,
    onBack: () -> Unit,
    onRename: (String) -> Unit,
    onArchive: () -> Unit,
    onToggleMute: (Boolean) -> Unit,
    onShareInvite: () -> Unit,
    onRevokeInvite: () -> Unit,
    onAddExpense: () -> Unit,
    onOpenExpense: (UUID) -> Unit,
    onAddPerson: (String, String) -> Unit,
    onRemovePerson: (UUID) -> Unit,
    onSettle: (SimplifiedDebt?) -> Unit,
    onOpenSettlement: (UUID) -> Unit,
    modifier: Modifier = Modifier,
) {
    var menuOpen by remember { mutableStateOf(false) }
    var showRename by remember { mutableStateOf(false) }
    var showArchive by remember { mutableStateOf(false) }
    var showAddPerson by remember { mutableStateOf(false) }
    var removePerson by remember { mutableStateOf<LocalPerson?>(null) }
    var section by remember { mutableStateOf(TripSection.EXPENSES) }
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = trip?.name ?: "Trip",
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    Box {
                        IconButton(onClick = { menuOpen = true }) {
                            Icon(Icons.Outlined.MoreVert, contentDescription = "Trip actions")
                        }
                        DropdownMenu(
                            expanded = menuOpen,
                            onDismissRequest = { menuOpen = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Rename trip") },
                                leadingIcon = {
                                    Icon(Icons.Outlined.Edit, contentDescription = null)
                                },
                                onClick = {
                                    menuOpen = false
                                    showRename = true
                                },
                            )
                            DropdownMenuItem(
                                text = { Text(if (isMuted) "Unmute activity" else "Mute activity") },
                                onClick = {
                                    menuOpen = false
                                    onToggleMute(!isMuted)
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Share invite link") },
                                onClick = {
                                    menuOpen = false
                                    onShareInvite()
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Revoke invite link") },
                                onClick = {
                                    menuOpen = false
                                    onRevokeInvite()
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Archive trip") },
                                leadingIcon = {
                                    Icon(Icons.Outlined.DeleteOutline, contentDescription = null)
                                },
                                onClick = {
                                    menuOpen = false
                                    showArchive = true
                                },
                            )
                        }
                    }
                },
            )
        },
        floatingActionButton = {
            when (section) {
                TripSection.EXPENSES -> ExtendedFloatingActionButton(
                    onClick = onAddExpense,
                    modifier = Modifier.testTag("addExpense"),
                    icon = { Icon(Icons.Outlined.Add, contentDescription = null) },
                    text = { Text("Add expense") },
                )
                TripSection.PEOPLE -> ExtendedFloatingActionButton(
                    onClick = { showAddPerson = true },
                    modifier = Modifier.testTag("addPerson"),
                    icon = { Icon(Icons.Outlined.Add, contentDescription = null) },
                    text = { Text("Add person") },
                )
                TripSection.BALANCES -> ExtendedFloatingActionButton(
                    onClick = { onSettle(null) },
                    icon = { Icon(Icons.Outlined.Add, contentDescription = null) },
                    text = { Text("Settle up") },
                )
                TripSection.OVERVIEW -> Unit
            }
        },
    ) { contentPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                TripSection.entries.forEach { candidate ->
                    FilterChip(
                        selected = section == candidate,
                        onClick = { section = candidate },
                        label = { Text(candidate.label) },
                    )
                }
            }
            when (section) {
                TripSection.EXPENSES -> ExpenseList(
                    expenses = content.expenses,
                    onOpenExpense = onOpenExpense,
                    modifier = Modifier.weight(1f),
                )
                TripSection.OVERVIEW -> TripOverview(
                    expenses = content.expenses,
                    peopleCount = content.people.size,
                    modifier = Modifier.weight(1f),
                )
                TripSection.PEOPLE -> PeopleList(
                    people = content.people,
                    currentUserId = currentUserId,
                    onRemove = { removePerson = it },
                    modifier = Modifier.weight(1f),
                )
                TripSection.BALANCES -> BalancesContent(
                    debts = content.simplifiedDebts,
                    settlements = content.settlements,
                    people = content.people,
                    onSettle = onSettle,
                    onOpenSettlement = onOpenSettlement,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    if (showRename && trip != null) {
        TripNameDialog(
            title = "Rename trip",
            action = "Save",
            initialName = trip.name,
            onDismiss = { showRename = false },
            onConfirm = {
                showRename = false
                onRename(it)
            },
        )
    }
    if (showArchive) {
        AlertDialog(
            onDismissRequest = { showArchive = false },
            title = { Text("Archive this trip?") },
            text = { Text("It will be removed for everyone after the change syncs.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showArchive = false
                        onArchive()
                    },
                ) {
                    Text("Archive")
                }
            },
            dismissButton = {
                TextButton(onClick = { showArchive = false }) {
                    Text("Cancel")
                }
            },
        )
    }
    if (showAddPerson) {
        AddPersonDialog(
            onDismiss = { showAddPerson = false },
            onConfirm = { email, name ->
                showAddPerson = false
                onAddPerson(email, name)
            },
        )
    }
    removePerson?.let { person ->
        AlertDialog(
            onDismissRequest = { removePerson = null },
            title = { Text("Remove ${person.displayName}?") },
            text = {
                Text("They will lose access after this change reaches the local Supabase service.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        removePerson = null
                        onRemovePerson(person.id)
                    },
                ) {
                    Text("Remove")
                }
            },
            dismissButton = {
                TextButton(onClick = { removePerson = null }) {
                    Text("Cancel")
                }
            },
        )
    }
}

private enum class TripSection(val label: String) {
    EXPENSES("Expenses"),
    BALANCES("Balances"),
    OVERVIEW("Overview"),
    PEOPLE("People"),
}

private fun List<LocalPerson>.nameFor(personId: UUID): String =
    firstOrNull { it.id == personId }?.displayName ?: "Member"

@Composable
private fun BalancesContent(
    debts: List<SimplifiedDebt>,
    settlements: List<Settlement>,
    people: List<LocalPerson>,
    onSettle: (SimplifiedDebt) -> Unit,
    onOpenSettlement: (UUID) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text(
                text = "Suggested repayments",
                modifier = Modifier.semantics { heading() },
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
        }
        if (debts.isEmpty()) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(18.dp)) {
                        Text("All settled", fontWeight = FontWeight.SemiBold)
                        Text(
                            text = "No repayment is needed for any currency.",
                            modifier = Modifier.padding(top = 4.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        } else {
            items(
                items = debts,
                key = { "${it.fromUser}-${it.toUser}-${it.currency}" },
            ) { debt ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "${people.nameFor(debt.fromUser)} pays ${people.nameFor(debt.toUser)}",
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = "${debt.amount.toPlainString()} ${debt.currency}",
                                modifier = Modifier.padding(top = 3.dp),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        TextButton(onClick = { onSettle(debt) }) {
                            Text("Settle")
                        }
                    }
                }
            }
        }
        item {
            Text(
                text = "Settlement history",
                modifier = Modifier
                    .padding(top = 8.dp)
                    .semantics { heading() },
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
        }
        if (settlements.isEmpty()) {
            item {
                Text(
                    text = "Recorded repayments will appear here.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            items(settlements, key = { it.id }) { settlement ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onOpenSettlement(settlement.id) },
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "${people.nameFor(settlement.fromUserId)} paid ${people.nameFor(settlement.toUserId)}",
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = settlement.settledAt.atZone(ZoneId.systemDefault())
                                    .format(tripDateFormatter),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        Text(
                            text = "${settlement.amount.amount.toPlainString()} ${settlement.amount.currency}",
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
            }
        }
        item { Spacer(modifier = Modifier.height(88.dp)) }
    }
}

@Composable
private fun ExpenseList(
    expenses: List<Expense>,
    onOpenExpense: (UUID) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (expenses.isEmpty()) {
        Column(
            modifier = modifier
                .fillMaxWidth()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = "No expenses yet",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "Add the first expense. It is saved on this device before syncing.",
                modifier = Modifier.padding(top = 6.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items(expenses, key = { it.id }) { expense ->
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .clickable { onOpenExpense(expense.id) },
                shape = RoundedCornerShape(16.dp),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = expense.description.orEmpty(),
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            text = expense.expenseDate.atZone(ZoneId.systemDefault())
                                .format(tripDateFormatter),
                            modifier = Modifier.padding(top = 3.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    Text(
                        text = "${expense.amount.amount.toPlainString()} ${expense.amount.currency}",
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
        item { Spacer(modifier = Modifier.height(88.dp)) }
    }
}

@Composable
private fun TripOverview(
    expenses: List<Expense>,
    peopleCount: Int,
    modifier: Modifier = Modifier,
) {
    val totals = expenses
        .groupBy { it.amount.currency }
        .mapValues { (_, rows) ->
            rows.fold(BigDecimal.ZERO) { total, expense -> total + expense.amount.amount }
        }
        .toSortedMap()
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text(
                text = "Trip summary",
                modifier = Modifier.semantics { heading() },
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(18.dp)) {
                    Text("$peopleCount people", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "${expenses.size} expenses",
                        modifier = Modifier.padding(top = 4.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        if (totals.isEmpty()) {
            item {
                Text(
                    text = "Spending totals appear here after you add an expense.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(18.dp)) {
                        Text(
                            text = "Total spent",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        totals.entries.forEachIndexed { index, (currency, amount) ->
                            if (index > 0) HorizontalDivider(modifier = Modifier.padding(vertical = 10.dp))
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text(currency)
                                Text(amount.toPlainString(), fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PeopleList(
    people: List<LocalPerson>,
    currentUserId: UUID,
    onRemove: (LocalPerson) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
    ) {
        items(people, key = { it.id }) { person ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = if (person.userId == currentUserId) {
                            "${person.displayName} (you)"
                        } else {
                            person.displayName
                        },
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = if (person.hasJoined) person.email else "${person.email} · invited",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                if (person.userId != currentUserId) {
                    TextButton(onClick = { onRemove(person) }) {
                        Text("Remove")
                    }
                }
            }
            HorizontalDivider()
        }
        item { Spacer(modifier = Modifier.height(88.dp)) }
    }
}

@Composable
private fun AddPersonDialog(
    onDismiss: () -> Unit,
    onConfirm: (String, String) -> Unit,
) {
    var email by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add a person") },
        text = {
            Column {
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Email") },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = displayName,
                    onValueChange = { displayName = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 10.dp),
                    label = { Text("Display name") },
                    supportingText = { Text("This requires the local Supabase service to be running.") },
                    singleLine = true,
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(email.trim(), displayName.trim()) },
                enabled = email.contains("@") && displayName.isNotBlank(),
            ) {
                Text("Add")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}

@Composable
private fun TripNameDialog(
    title: String,
    action: String,
    initialName: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    var name by remember(initialName) { mutableStateOf(initialName) }
    val focusManager = LocalFocusManager.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Trip name") },
                supportingText = { Text("Trips are private to the people you add.") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(
                    onDone = {
                        if (name.isNotBlank()) {
                            focusManager.clearFocus()
                            onConfirm(name.trim())
                        }
                    },
                ),
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(name.trim()) },
                enabled = name.isNotBlank(),
            ) {
                Text(action)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}

private val tripDateFormatter: DateTimeFormatter =
    DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
