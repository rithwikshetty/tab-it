package com.rithwikshetty.tab

import com.rithwikshetty.tab.domain.PaymentMethod
import com.rithwikshetty.tab.ui.expenses.ExpenseForm
import com.rithwikshetty.tab.ui.expenses.ExpenseFormInput
import com.rithwikshetty.tab.ui.expenses.ExpenseSplitMode
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ExpenseFormTest {
    private val userId = UUID.fromString("11111111-1111-1111-1111-111111111111")
    private val friendId = UUID.fromString("22222222-2222-2222-2222-222222222222")
    private val tripId = UUID.fromString("33333333-3333-3333-3333-333333333333")
    private val now = Instant.parse("2026-07-29T12:00:00Z")

    @Test
    fun equalSplitAndMultiplePayersRemainExact() {
        val expense = ExpenseForm.build(
            input(
                payerAmounts = mapOf(userId to "6.00", friendId to "4.00"),
                participants = setOf(userId, friendId),
            ),
            tripId,
            userId,
            now,
        )

        assertEquals(BigDecimal("10.00"), expense.amount.amount)
        assertEquals(listOf(BigDecimal("6.00"), BigDecimal("4.00")), expense.payments.map { it.amountPaid })
        assertEquals(0, expense.splits.sumOf { it.amountOwed }.compareTo(BigDecimal("10.00")))
    }

    @Test
    fun exactSplitMustReconcile() {
        val invalid = input(
            payerAmounts = mapOf(userId to "10.00"),
            participants = setOf(userId, friendId),
        ).copy(
            splitMode = ExpenseSplitMode.EXACT,
            exactAmountText = mapOf(userId to "8.00", friendId to "1.00"),
        )

        assertThrows(IllegalArgumentException::class.java) {
            ExpenseForm.build(invalid, tripId, userId, now)
        }
    }

    @Test
    fun payerAmountsMustReconcile() {
        val invalid = input(
            payerAmounts = mapOf(userId to "9.99"),
            participants = setOf(userId),
        )

        assertThrows(IllegalArgumentException::class.java) {
            ExpenseForm.build(invalid, tripId, userId, now)
        }
    }

    private fun input(
        payerAmounts: Map<UUID, String>,
        participants: Set<UUID>,
    ): ExpenseFormInput = ExpenseFormInput(
        description = "Dinner",
        amountText = "10.00",
        currency = "GBP",
        categoryId = null,
        expenseDate = now,
        paymentMethod = PaymentMethod.CARD,
        payerAmountText = payerAmounts,
        participantIds = participants,
        splitMode = ExpenseSplitMode.EQUAL,
        exactAmountText = emptyMap(),
    )
}
