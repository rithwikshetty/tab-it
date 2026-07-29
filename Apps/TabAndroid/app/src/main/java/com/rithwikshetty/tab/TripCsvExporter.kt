package com.rithwikshetty.tab

import com.rithwikshetty.tab.data.LocalCategory
import com.rithwikshetty.tab.data.LocalPerson
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.Settlement
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

object TripCsvExporter {
    fun generate(
        expenses: List<Expense>,
        settlements: List<Settlement>,
        people: List<LocalPerson>,
        categories: List<LocalCategory>,
    ): String {
        val names = people.associate { it.id to it.displayName }
        val categoryNames = categories.associate { it.id to it.name }
        val rows = mutableListOf(
            listOf(
                "Type",
                "Date",
                "Description",
                "Currency",
                "Amount",
                "From or paid by",
                "To or split between",
                "Category",
                "Payment method",
            ),
        )
        expenses.sortedWith(compareBy<Expense> { it.expenseDate }.thenBy { it.id }).forEach { item ->
            rows += listOf(
                "Expense",
                exportDate.format(item.expenseDate.atZone(ZoneId.systemDefault())),
                item.description.orEmpty(),
                item.amount.currency,
                item.amount.amount.toPlainString(),
                item.payments.joinToString("; ") {
                    "${names.nameFor(it.payerId)} ${it.amountPaid.toPlainString()}"
                },
                item.splits.joinToString("; ") {
                    "${names.nameFor(it.participantId)} ${it.amountOwed.toPlainString()}"
                },
                item.categoryId?.let(categoryNames::get).orEmpty(),
                item.paymentMethod.name.lowercase().replace('_', ' '),
            )
        }
        settlements.sortedWith(compareBy<Settlement> { it.settledAt }.thenBy { it.id }).forEach { item ->
            rows += listOf(
                "Settlement",
                exportDate.format(item.settledAt.atZone(ZoneId.systemDefault())),
                item.note.orEmpty(),
                item.amount.currency,
                item.amount.amount.toPlainString(),
                names.nameFor(item.fromUserId),
                names.nameFor(item.toUserId),
                "",
                "",
            )
        }
        return rows.joinToString("\n") { row -> row.joinToString(",") { it.csvField() } } + "\n"
    }

    private fun Map<UUID, String>.nameFor(id: UUID): String = this[id] ?: "Unknown member"

    private fun String.csvField(): String =
        if (contains(',') || contains('"') || contains('\n')) {
            "\"${replace("\"", "\"\"")}\""
        } else {
            this
        }

    private val exportDate: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
}
