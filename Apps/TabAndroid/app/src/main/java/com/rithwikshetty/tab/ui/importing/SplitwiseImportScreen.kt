package com.rithwikshetty.tab.ui.importing

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.rithwikshetty.tab.ui.app.ImportPreviewUiState
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SplitwiseImportScreen(
    preview: ImportPreviewUiState?,
    isWorking: Boolean,
    onBack: () -> Unit,
    onChooseFile: (String) -> Unit,
    onClearPreview: () -> Unit,
    onImport: (String, String, (UUID) -> Unit) -> Unit,
    onImported: (UUID) -> Unit,
    modifier: Modifier = Modifier,
) {
    var tripName by remember(preview?.sourceName) {
        mutableStateOf(preview?.sourceName?.substringBeforeLast('.') ?: "Imported trip")
    }
    var selfPerson by remember(preview?.sourceName) {
        mutableStateOf(preview?.result?.people?.firstOrNull())
    }
    val picker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        if (uri != null) onChooseFile(uri.toString())
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Import from Splitwise") },
                navigationIcon = {
                    IconButton(
                        onClick = {
                            onClearPreview()
                            onBack()
                        },
                    ) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        if (preview == null) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(24.dp),
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    text = "Choose a Splitwise group CSV",
                    modifier = Modifier.semantics { heading() },
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "Tab will parse the file locally and show a summary before creating anything.",
                    modifier = Modifier.padding(top = 8.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = {
                        picker.launch(
                            arrayOf("text/csv", "text/*", "application/vnd.ms-excel"),
                        )
                    },
                    modifier = Modifier.padding(top = 20.dp),
                    enabled = !isWorking,
                ) {
                    Text("Choose CSV")
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
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
                                text = preview.sourceName,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = listOf(
                                    preview.result.expenses.size.countLabel("expense"),
                                    preview.result.settlements.size.countLabel("settlement"),
                                    preview.result.people.size.countLabel("person", "people"),
                                ).joinToString(),
                                modifier = Modifier.padding(top = 4.dp),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            if (preview.result.warnings.isNotEmpty()) {
                                Text(
                                    text = "${preview.result.warnings.size} rows need attention",
                                    modifier = Modifier.padding(top = 4.dp),
                                    color = MaterialTheme.colorScheme.error,
                                )
                            }
                        }
                    }
                }
                item {
                    OutlinedTextField(
                        value = tripName,
                        onValueChange = { tripName = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp),
                        label = { Text("Trip name") },
                        singleLine = true,
                    )
                }
                item {
                    Text(
                        text = "Which person is you?",
                        modifier = Modifier
                            .padding(horizontal = 16.dp)
                            .semantics { heading() },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                items(preview.result.people, key = { it }) { person ->
                    Row(modifier = Modifier.padding(horizontal = 16.dp)) {
                        FilterChip(
                            selected = selfPerson == person,
                            onClick = { selfPerson = person },
                            label = { Text(person) },
                        )
                    }
                }
                if (preview.result.warnings.isNotEmpty()) {
                    item {
                        Text(
                            text = "Warnings",
                            modifier = Modifier
                                .padding(horizontal = 16.dp)
                                .semantics { heading() },
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    items(preview.result.warnings, key = { "${it.line}-${it.message}" }) {
                        Text(
                            text = "Line ${it.line}: ${it.message}",
                            modifier = Modifier.padding(horizontal = 16.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        OutlinedButton(
                            onClick = {
                                onClearPreview()
                                picker.launch(
                                    arrayOf("text/csv", "text/*", "application/vnd.ms-excel"),
                                )
                            },
                            enabled = !isWorking,
                        ) {
                            Text("Choose another")
                        }
                        Button(
                            onClick = {
                                val selected = selfPerson ?: return@Button
                                onImport(tripName, selected) { onImported(it) }
                            },
                            enabled = !isWorking &&
                                tripName.isNotBlank() &&
                                selfPerson != null,
                        ) {
                            Text("Import trip")
                        }
                    }
                }
            }
        }
    }
}

private fun Int.countLabel(singular: String, plural: String = "${singular}s"): String =
    "$this ${if (this == 1) singular else plural}"
