package com.rithwikshetty.tab.ui.expenses

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.rithwikshetty.tab.data.LocalCategory
import com.rithwikshetty.tab.data.LocalPerson
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.PaymentMethod
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpenseEditorScreen(
    tripId: UUID,
    currentUserId: UUID,
    people: List<LocalPerson>,
    categories: List<LocalCategory>,
    existing: Expense?,
    isWorking: Boolean,
    onBack: () -> Unit,
    onSave: (Expense, String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    var initialized by remember(existing?.id) { mutableStateOf(false) }
    var description by remember(existing?.id) { mutableStateOf(existing?.description.orEmpty()) }
    var amountText by remember(existing?.id) {
        mutableStateOf(existing?.amount?.amount?.toPlainString().orEmpty())
    }
    var currency by remember(existing?.id) {
        mutableStateOf(existing?.amount?.currency ?: "GBP")
    }
    var selectedCategoryId by remember(existing?.id) { mutableStateOf(existing?.categoryId) }
    var paymentMethod by remember(existing?.id) {
        mutableStateOf(existing?.paymentMethod ?: PaymentMethod.CARD)
    }
    var splitMode by remember(existing?.id) {
        mutableStateOf(
            if (existing?.splits?.firstOrNull()?.splitType?.name == "EXACT") {
                ExpenseSplitMode.EXACT
            } else {
                ExpenseSplitMode.EQUAL
            },
        )
    }
    var expenseDate by remember(existing?.id) {
        mutableStateOf(existing?.expenseDate ?: Instant.now())
    }
    val payerAmounts = remember(existing?.id) { mutableStateMapOf<UUID, String>() }
    val participants = remember(existing?.id) { mutableStateMapOf<UUID, Boolean>() }
    val exactAmounts = remember(existing?.id) { mutableStateMapOf<UUID, String>() }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showDatePicker by remember { mutableStateOf(false) }
    var receiptUri by remember(existing?.id) { mutableStateOf<String?>(null) }
    val receiptPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent(),
    ) { uri ->
        receiptUri = uri?.toString()
    }

    val currentPersonId = people.firstOrNull { it.userId == currentUserId }?.id
    val defaultPayerId = currentPersonId ?: people.firstOrNull()?.id
    LaunchedEffect(people, existing?.id) {
        if (!initialized && people.isNotEmpty()) {
            existing?.let { expense ->
                expense.payments.forEach {
                    payerAmounts[it.payerId] = it.amountPaid.toPlainString()
                }
                expense.splits.forEach {
                    participants[it.participantId] = true
                    exactAmounts[it.participantId] = it.amountOwed.toPlainString()
                }
            } ?: run {
                people.forEach { participants[it.id] = true }
                if (defaultPayerId != null) payerAmounts[defaultPayerId] = amountText
            }
            initialized = true
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(if (existing == null) "New expense" else "Edit expense") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(
                        onClick = {
                            errorMessage = null
                            val effectivePayers = payerAmounts.toMap()
                                .takeUnless { amounts -> amounts.values.none(String::isNotBlank) }
                                ?: defaultPayerId?.let { mapOf(it to amountText) }
                                ?: emptyMap()
                            val effectiveParticipants = participants
                                .filterValues { it }
                                .keys
                                .ifEmpty { people.map(LocalPerson::id).toSet() }
                            val input = ExpenseFormInput(
                                description = description,
                                amountText = amountText,
                                currency = currency,
                                categoryId = selectedCategoryId,
                                expenseDate = expenseDate,
                                paymentMethod = paymentMethod,
                                payerAmountText = effectivePayers,
                                participantIds = effectiveParticipants,
                                splitMode = splitMode,
                                exactAmountText = exactAmounts.toMap(),
                            )
                            runCatching {
                                ExpenseForm.build(
                                    input = input,
                                    tripId = tripId,
                                    currentUserId = currentUserId,
                                    now = Instant.now(),
                                    existing = existing,
                                )
                            }.onSuccess {
                                onSave(it, receiptUri)
                                onBack()
                            }.onFailure {
                                errorMessage = it.message ?: "Check the expense details."
                            }
                        },
                        modifier = Modifier.testTag("saveExpense"),
                        enabled = !isWorking && people.isNotEmpty(),
                    ) {
                        Text("Save")
                    }
                },
            )
        },
    ) { contentPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                ) {
                    if (errorMessage != null) {
                        Text(
                            text = checkNotNull(errorMessage),
                            modifier = Modifier
                                .fillMaxWidth()
                                .semantics { liveRegion = LiveRegionMode.Assertive }
                                .padding(bottom = 12.dp),
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                    OutlinedTextField(
                        value = description,
                        onValueChange = { description = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("expenseDescription"),
                        label = { Text("Description") },
                        singleLine = true,
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        OutlinedTextField(
                            value = amountText,
                            onValueChange = { newValue ->
                                amountText = newValue
                                if (existing == null &&
                                    defaultPayerId != null &&
                                    (
                                        payerAmounts.isEmpty() ||
                                            payerAmounts.keys == setOf(defaultPayerId)
                                    )
                                ) {
                                    payerAmounts[defaultPayerId] = newValue
                                }
                            },
                            modifier = Modifier
                                .weight(1f)
                                .testTag("expenseAmount"),
                            label = { Text("Amount") },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        )
                        Spacer(modifier = Modifier.width(10.dp))
                        MenuSelector(
                            label = currency,
                            options = currencyOptions,
                            optionLabel = { it },
                            onSelect = { currency = it },
                        )
                    }
                    MenuSelector(
                        label = categories.firstOrNull { it.id == selectedCategoryId }?.name
                            ?: "No category",
                        options = listOf<LocalCategory?>(null) + categories,
                        optionLabel = { it?.name ?: "No category" },
                        onSelect = { selectedCategoryId = it?.id },
                        modifier = Modifier.padding(top = 12.dp),
                    )
                    OutlinedButton(
                        onClick = { showDatePicker = true },
                        modifier = Modifier.padding(top = 12.dp),
                    ) {
                        Text(
                            expenseDate.atZone(ZoneId.systemDefault())
                                .format(expenseDateFormatter),
                        )
                    }
                }
            }

            item {
                FormSection(title = "Receipt") {
                    Text(
                        text = when {
                            receiptUri != null -> "New receipt selected"
                            existing?.receiptStoragePath != null -> "Receipt attached"
                            else -> "No receipt"
                        },
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedButton(
                        onClick = { receiptPicker.launch("image/*") },
                        modifier = Modifier.padding(top = 8.dp),
                    ) {
                        Text(
                            if (receiptUri != null || existing?.receiptStoragePath != null) {
                                "Replace receipt"
                            } else {
                                "Add receipt"
                            },
                        )
                    }
                }
            }

            item {
                FormSection(title = "Payment method") {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        PaymentMethod.entries.forEach { method ->
                            FilterChip(
                                selected = paymentMethod == method,
                                onClick = { paymentMethod = method },
                                label = { Text(method.displayName()) },
                            )
                        }
                    }
                }
            }

            item {
                FormSection(title = "Who paid") {
                    people.forEachIndexed { index, person ->
                        PersonAmountRow(
                            person = person,
                            currentUserId = currentUserId,
                            value = payerAmounts[person.id].orEmpty(),
                            label = "Paid",
                            onValueChange = { payerAmounts[person.id] = it },
                        )
                        if (index < people.lastIndex) HorizontalDivider()
                    }
                }
            }

            item {
                FormSection(title = "How it is split") {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ExpenseSplitMode.entries.forEach { mode ->
                            FilterChip(
                                selected = splitMode == mode,
                                onClick = { splitMode = mode },
                                label = { Text(mode.name.lowercase().replaceFirstChar(Char::uppercase)) },
                            )
                        }
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    people.forEachIndexed { index, person ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Checkbox(
                                checked = participants[person.id] == true,
                                onCheckedChange = { participants[person.id] = it },
                            )
                            Text(
                                text = person.displayLabel(currentUserId),
                                modifier = Modifier.weight(1f),
                                style = MaterialTheme.typography.bodyLarge,
                            )
                            if (splitMode == ExpenseSplitMode.EXACT &&
                                participants[person.id] == true
                            ) {
                                OutlinedTextField(
                                    value = exactAmounts[person.id].orEmpty(),
                                    onValueChange = { exactAmounts[person.id] = it },
                                    modifier = Modifier.width(112.dp),
                                    label = { Text("Owes") },
                                    singleLine = true,
                                    keyboardOptions = KeyboardOptions(
                                        keyboardType = KeyboardType.Decimal,
                                    ),
                                )
                            }
                        }
                        if (index < people.lastIndex) HorizontalDivider()
                    }
                }
            }
            item { Spacer(modifier = Modifier.height(24.dp)) }
        }
    }

    if (showDatePicker) {
        val datePickerState = rememberDatePickerState(
            initialSelectedDateMillis = expenseDate.toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        datePickerState.selectedDateMillis?.let {
                            expenseDate = Instant.ofEpochMilli(it)
                        }
                        showDatePicker = false
                    },
                ) {
                    Text("Choose")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) {
                    Text("Cancel")
                }
            },
        ) {
            DatePicker(state = datePickerState)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpenseDetailScreen(
    expense: Expense?,
    people: List<LocalPerson>,
    category: LocalCategory?,
    onLoadReceipt: (String, (ByteArray) -> Unit) -> Unit,
    onBack: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var confirmDelete by remember { mutableStateOf(false) }
    var receiptBytes by remember(expense?.id) { mutableStateOf<ByteArray?>(null) }
    LaunchedEffect(expense?.receiptStoragePath) {
        expense?.receiptStoragePath?.let { path ->
            onLoadReceipt(path) { receiptBytes = it }
        }
    }
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = expense?.description ?: "Expense",
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
                    IconButton(onClick = onEdit, enabled = expense != null) {
                        Icon(Icons.Outlined.Edit, contentDescription = "Edit expense")
                    }
                    IconButton(
                        onClick = { confirmDelete = true },
                        enabled = expense != null,
                    ) {
                        Icon(Icons.Outlined.DeleteOutline, contentDescription = "Delete expense")
                    }
                },
            )
        },
    ) { contentPadding ->
        if (expense == null) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(contentPadding)
                    .padding(24.dp),
                verticalArrangement = Arrangement.Center,
            ) {
                Text("This expense is no longer available.")
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(contentPadding),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                item {
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp),
                    ) {
                        Column(modifier = Modifier.padding(18.dp)) {
                            Text(
                                text = "${expense.amount.amount.toPlainString()} ${expense.amount.currency}",
                                modifier = Modifier.semantics { heading() },
                                style = MaterialTheme.typography.headlineMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = category?.name ?: "No category",
                                modifier = Modifier.padding(top = 6.dp),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                text = expense.expenseDate.atZone(ZoneId.systemDefault())
                                    .format(expenseDateFormatter),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                text = expense.paymentMethod.displayName(),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                if (expense.receiptStoragePath != null) {
                    item {
                        FormSection("Receipt") {
                            val bytes = receiptBytes
                            if (bytes == null) {
                                Text(
                                    "Loading receipt",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            } else {
                                val bitmap = remember(bytes) {
                                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                                }
                                if (bitmap == null) {
                                    Text(
                                        "Couldn't display receipt",
                                        color = MaterialTheme.colorScheme.error,
                                    )
                                } else {
                                    Image(
                                        bitmap = bitmap.asImageBitmap(),
                                        contentDescription = "Receipt image",
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .height(260.dp),
                                        contentScale = ContentScale.Fit,
                                    )
                                }
                            }
                        }
                    }
                }
                item {
                    DetailLedgerSection(
                        title = "Paid by",
                        rows = expense.payments.map {
                            people.nameFor(it.payerId) to it.amountPaid.toPlainString()
                        },
                        currency = expense.amount.currency,
                    )
                }
                item {
                    DetailLedgerSection(
                        title = "Split between",
                        rows = expense.splits.map {
                            people.nameFor(it.participantId) to it.amountOwed.toPlainString()
                        },
                        currency = expense.amount.currency,
                    )
                }
            }
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete expense?") },
            text = { Text("It will be removed for everyone after the change syncs.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmDelete = false
                        onDelete()
                    },
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
private fun FormSection(
    title: String,
    content: @Composable () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
    ) {
        Text(
            text = title,
            modifier = Modifier.semantics { heading() },
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp),
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                content()
            }
        }
    }
}

@Composable
private fun PersonAmountRow(
    person: LocalPerson,
    currentUserId: UUID,
    value: String,
    label: String,
    onValueChange: (String) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(person.displayLabel(currentUserId), style = MaterialTheme.typography.bodyLarge)
            Text(
                text = if (person.hasJoined) "Joined" else person.email,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier
                .width(118.dp)
                .testTag("payerAmount-${person.id}"),
            label = { Text(label) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        )
    }
}

@Composable
private fun <T> MenuSelector(
    label: String,
    options: List<T>,
    optionLabel: (T) -> String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    Column(modifier = modifier) {
        OutlinedButton(onClick = { expanded = true }) {
            Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(optionLabel(option)) },
                    onClick = {
                        expanded = false
                        onSelect(option)
                    },
                )
            }
        }
    }
}

@Composable
private fun DetailLedgerSection(
    title: String,
    rows: List<Pair<String, String>>,
    currency: String,
) {
    FormSection(title) {
        rows.forEachIndexed { index, (name, amount) ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 9.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(name)
                Text("$amount $currency", fontWeight = FontWeight.Medium)
            }
            if (index < rows.lastIndex) HorizontalDivider()
        }
    }
}

private fun LocalPerson.displayLabel(currentUserId: UUID): String =
    if (userId == currentUserId) "You" else displayName

private fun List<LocalPerson>.nameFor(personId: UUID): String =
    firstOrNull { it.id == personId }?.displayName ?: "Member"

private fun PaymentMethod.displayName(): String =
    name.lowercase().replace('_', ' ').replaceFirstChar(Char::uppercase)

private val currencyOptions = listOf("GBP", "EUR", "USD", "INR", "AUD", "CAD")

private val expenseDateFormatter: DateTimeFormatter =
    DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
