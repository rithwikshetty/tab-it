package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

public enum class SplitType {
    EQUAL,
    EXACT,
    PERCENTAGE,
    SHARES,
    ADJUSTMENT,
}

public enum class PaymentMethod {
    CASH,
    CARD,
    BANK_TRANSFER,
}

public data class ExpenseSplit(
    public val participantId: UUID,
    public val amountOwed: BigDecimal,
    public val splitType: SplitType,
    public val shareUnits: BigDecimal? = null,
    public val percentage: BigDecimal? = null,
)

public data class Payment(
    public val payerId: UUID,
    public val amountPaid: BigDecimal,
    public val paymentMode: SplitType,
)

public data class Expense(
    public val id: UUID = UUID.randomUUID(),
    public val tripId: UUID,
    public val amount: Money,
    public val categoryId: UUID? = null,
    public val description: String? = null,
    public val receiptStoragePath: String? = null,
    public val paymentMethod: PaymentMethod = PaymentMethod.CARD,
    public val expenseDate: Instant,
    public val payments: List<Payment>,
    public val splits: List<ExpenseSplit>,
    public val createdBy: UUID,
    public val createdAt: Instant,
    public val updatedAt: Instant,
    public val deletedAt: Instant? = null,
)

public data class Settlement(
    public val id: UUID = UUID.randomUUID(),
    public val tripId: UUID,
    public val fromUserId: UUID,
    public val toUserId: UUID,
    public val amount: Money,
    public val note: String? = null,
    public val settledAt: Instant,
    public val createdBy: UUID,
    public val createdAt: Instant,
    public val updatedAt: Instant,
    public val deletedAt: Instant? = null,
)
