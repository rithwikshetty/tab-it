package com.rithwikshetty.tab.ui.expenses

import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.Money
import com.rithwikshetty.tab.domain.Payment
import com.rithwikshetty.tab.domain.PaymentMethod
import com.rithwikshetty.tab.domain.SplitCalculator
import com.rithwikshetty.tab.domain.SplitType
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

enum class ExpenseSplitMode {
    EQUAL,
    EXACT,
}

data class ExpenseFormInput(
    val description: String,
    val amountText: String,
    val currency: String,
    val categoryId: UUID?,
    val expenseDate: Instant,
    val paymentMethod: PaymentMethod,
    val payerAmountText: Map<UUID, String>,
    val participantIds: Set<UUID>,
    val splitMode: ExpenseSplitMode,
    val exactAmountText: Map<UUID, String>,
)

object ExpenseForm {
    fun build(
        input: ExpenseFormInput,
        tripId: UUID,
        currentUserId: UUID,
        now: Instant,
        existing: Expense? = null,
    ): Expense {
        val description = input.description.trim()
        require(description.isNotEmpty()) { "Description is required." }
        val money = runCatching { Money.parse(input.amountText.trim(), input.currency) }
            .getOrElse { throw IllegalArgumentException("Enter a valid amount.") }
        require(money.amount > BigDecimal.ZERO) { "Amount must be greater than zero." }

        val payments = input.payerAmountText.mapNotNull { (personId, rawAmount) ->
            val amount = rawAmount.trim().takeIf(String::isNotEmpty)?.toBigDecimalOrNull()
                ?: return@mapNotNull null
            if (amount.compareTo(BigDecimal.ZERO) == 0) return@mapNotNull null
            require(amount > BigDecimal.ZERO) { "Payer amounts cannot be negative." }
            Payment(personId, amount, SplitType.EXACT)
        }.sortedBy { it.payerId.toString() }
        require(payments.isNotEmpty()) { "At least one payer is required." }
        val paidTotal = payments.fold(BigDecimal.ZERO) { total, payment ->
            total + payment.amountPaid
        }
        require(paidTotal.compareTo(money.amount) == 0) {
            "Payer amounts must add up to ${money.amount.toPlainString()} ${money.currency}."
        }

        val participants = input.participantIds.sortedBy(UUID::toString)
        val exactAmounts = if (input.splitMode == ExpenseSplitMode.EXACT) {
            participants.associateWith { personId ->
                input.exactAmountText[personId]?.trim()?.toBigDecimalOrNull()
                    ?: throw IllegalArgumentException("Every participant needs an exact amount.")
            }
        } else {
            null
        }
        val splits = SplitCalculator.calculate(
            totalAmount = money.amount,
            currency = money.currency,
            participants = participants,
            splitType = when (input.splitMode) {
                ExpenseSplitMode.EQUAL -> SplitType.EQUAL
                ExpenseSplitMode.EXACT -> SplitType.EXACT
            },
            exactAmounts = exactAmounts,
        )

        return Expense(
            id = existing?.id ?: UUID.randomUUID(),
            tripId = tripId,
            amount = money,
            categoryId = input.categoryId,
            description = description,
            receiptStoragePath = existing?.receiptStoragePath,
            paymentMethod = input.paymentMethod,
            expenseDate = input.expenseDate,
            payments = payments,
            splits = splits,
            createdBy = existing?.createdBy ?: currentUserId,
            createdAt = existing?.createdAt ?: now,
            updatedAt = now,
            deletedAt = null,
        )
    }
}
