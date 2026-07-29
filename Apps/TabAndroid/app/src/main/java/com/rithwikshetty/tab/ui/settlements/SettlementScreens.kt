package com.rithwikshetty.tab.ui.settlements

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.rithwikshetty.tab.data.LocalPerson
import com.rithwikshetty.tab.domain.Settlement
import com.rithwikshetty.tab.domain.SimplifiedDebt
import java.math.BigDecimal
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettlementEditorScreen(
    people: List<LocalPerson>,
    existing: Settlement?,
    suggestion: SimplifiedDebt?,
    isWorking: Boolean,
    onBack: () -> Unit,
    onSave: (
        fromPersonId: UUID,
        toPersonId: UUID,
        amountText: String,
        currency: String,
        note: String?,
        existing: Settlement?,
    ) -> Unit,
    modifier: Modifier = Modifier,
) {
    var fromId by remember(existing?.id, suggestion) {
        mutableStateOf(existing?.fromUserId ?: suggestion?.fromUser ?: people.firstOrNull()?.id)
    }
    var toId by remember(existing?.id, suggestion) {
        mutableStateOf(
            existing?.toUserId ?: suggestion?.toUser
                ?: people.firstOrNull { it.id != fromId }?.id,
        )
    }
    var amountText by remember(existing?.id, suggestion) {
        mutableStateOf(
            existing?.amount?.amount?.toPlainString()
                ?: suggestion?.amount?.toPlainString().orEmpty(),
        )
    }
    var currency by remember(existing?.id, suggestion) {
        mutableStateOf(existing?.amount?.currency ?: suggestion?.currency ?: "GBP")
    }
    var note by remember(existing?.id) { mutableStateOf(existing?.note.orEmpty()) }
    var errorMessage by remember(existing?.id, suggestion) { mutableStateOf<String?>(null) }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(if (existing == null) "Record repayment" else "Edit repayment") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(
                        onClick = {
                            val from = fromId
                            val to = toId
                            errorMessage = when {
                                from == null || to == null -> "Choose both people."
                                from == to -> "Choose two different people."
                                runCatching { BigDecimal(amountText.trim()) }
                                    .getOrNull()
                                    ?.let { it <= BigDecimal.ZERO } != false ->
                                    "Enter an amount greater than zero."
                                currency.trim().length != 3 ->
                                    "Use a three-letter currency code."
                                else -> null
                            }
                            if (errorMessage == null) {
                                onSave(
                                    checkNotNull(from),
                                    checkNotNull(to),
                                    amountText,
                                    currency,
                                    note,
                                    existing,
                                )
                                onBack()
                            }
                        },
                        modifier = Modifier.testTag("saveSettlement"),
                        enabled = !isWorking && people.size >= 2,
                    ) {
                        Text("Save")
                    }
                },
            )
        },
    ) { contentPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (errorMessage != null) {
                Text(
                    text = checkNotNull(errorMessage),
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { liveRegion = LiveRegionMode.Assertive },
                    color = MaterialTheme.colorScheme.error,
                )
            }
            Text(
                text = "Who paid whom",
                modifier = Modifier.semantics { heading() },
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
            PersonSelector(
                label = "Paid by",
                selected = people.firstOrNull { it.id == fromId },
                people = people,
                onSelect = { person ->
                    fromId = person.id
                    if (toId == person.id) {
                        toId = people.firstOrNull { it.id != person.id }?.id
                    }
                },
            )
            PersonSelector(
                label = "Paid to",
                selected = people.firstOrNull { it.id == toId },
                people = people,
                onSelect = { person ->
                    toId = person.id
                    if (fromId == person.id) {
                        fromId = people.firstOrNull { it.id != person.id }?.id
                    }
                },
            )
            Row(modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = amountText,
                    onValueChange = { amountText = it },
                    modifier = Modifier
                        .weight(1f)
                        .testTag("settlementAmount"),
                    label = { Text("Amount") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                )
                Spacer(modifier = Modifier.width(10.dp))
                OutlinedTextField(
                    value = currency,
                    onValueChange = { currency = it.uppercase().take(3) },
                    modifier = Modifier.width(104.dp),
                    label = { Text("Currency") },
                    singleLine = true,
                )
            }
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Note (optional)") },
                minLines = 2,
                maxLines = 4,
            )
            if (people.size < 2) {
                Text(
                    text = "Add at least two people before recording a repayment.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettlementDetailScreen(
    settlement: Settlement?,
    people: List<LocalPerson>,
    onBack: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var confirmDelete by remember { mutableStateOf(false) }
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Repayment") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = onEdit, enabled = settlement != null) {
                        Icon(Icons.Outlined.Edit, contentDescription = "Edit repayment")
                    }
                    IconButton(
                        onClick = { confirmDelete = true },
                        enabled = settlement != null,
                    ) {
                        Icon(Icons.Outlined.DeleteOutline, contentDescription = "Delete repayment")
                    }
                },
            )
        },
    ) { contentPadding ->
        if (settlement == null) {
            Text(
                text = "This repayment is no longer available.",
                modifier = Modifier.padding(contentPadding).padding(24.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(contentPadding)
                    .padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    text = "${people.nameFor(settlement.fromUserId)} paid " +
                        people.nameFor(settlement.toUserId),
                    modifier = Modifier.semantics { heading() },
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "${settlement.amount.amount.toPlainString()} " +
                        settlement.amount.currency,
                    style = MaterialTheme.typography.headlineMedium,
                )
                Text(
                    text = settlement.settledAt.atZone(ZoneId.systemDefault())
                        .format(settlementDateFormatter),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                settlement.note?.let {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Text(text = it, modifier = Modifier.padding(16.dp))
                    }
                }
            }
        }
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete this repayment?") },
            text = { Text("Balances will be recalculated after the local change syncs.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmDelete = false
                        onDelete()
                    },
                    modifier = Modifier.testTag("confirmDeleteSettlement"),
                ) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) {
                    Text("Cancel")
                }
            },
        )
    }
}

@Composable
private fun PersonSelector(
    label: String,
    selected: LocalPerson?,
    people: List<LocalPerson>,
    onSelect: (LocalPerson) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Column {
        Text(
            text = label,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.labelLarge,
        )
        OutlinedButton(
            onClick = { expanded = true },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(selected?.displayName ?: "Choose a person")
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            people.forEach { person ->
                DropdownMenuItem(
                    text = { Text(person.displayName) },
                    onClick = {
                        expanded = false
                        onSelect(person)
                    },
                )
            }
        }
    }
}

private fun List<LocalPerson>.nameFor(id: UUID): String =
    firstOrNull { it.id == id }?.displayName ?: "Member"

private val settlementDateFormatter: DateTimeFormatter =
    DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
