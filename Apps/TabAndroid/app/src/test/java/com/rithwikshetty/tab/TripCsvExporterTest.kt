package com.rithwikshetty.tab

import com.rithwikshetty.tab.data.LocalPerson
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.ExpenseSplit
import com.rithwikshetty.tab.domain.Money
import com.rithwikshetty.tab.domain.Payment
import com.rithwikshetty.tab.domain.PaymentMethod
import com.rithwikshetty.tab.domain.SplitType
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertTrue
import org.junit.Test

class TripCsvExporterTest {
    @Test
    fun exportQuotesTextAndPreservesExactDecimalLedger() {
        val tripId = UUID.randomUUID()
        val userId = UUID.randomUUID()
        val personId = UUID.randomUUID()
        val expense = Expense(
            id = UUID.randomUUID(),
            tripId = tripId,
            amount = Money.parse("12.34", "GBP"),
            description = "Dinner, drinks",
            paymentMethod = PaymentMethod.CARD,
            expenseDate = Instant.parse("2026-07-29T12:00:00Z"),
            payments = listOf(Payment(personId, BigDecimal("12.34"), SplitType.EXACT)),
            splits = listOf(ExpenseSplit(personId, BigDecimal("12.34"), SplitType.EXACT)),
            createdBy = userId,
            createdAt = Instant.parse("2026-07-29T12:00:00Z"),
            updatedAt = Instant.parse("2026-07-29T12:00:00Z"),
        )

        val csv = TripCsvExporter.generate(
            expenses = listOf(expense),
            settlements = emptyList(),
            people = listOf(
                LocalPerson(personId, userId, "mock@tab.local", "Test User", true, tripId),
            ),
            categories = emptyList(),
        )

        assertTrue(csv.startsWith("Type,Date,Description"))
        assertTrue(csv.contains("\"Dinner, drinks\""))
        assertTrue(csv.contains(",GBP,12.34,"))
        assertTrue(csv.endsWith("\n"))
    }
}
