package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.util.UUID

public sealed class PaymentCalculatorException(message: String) : IllegalArgumentException(message) {
    public data object EmptyPayers : PaymentCalculatorException("Payers cannot be empty.")
    public data class DuplicatePayer(public val id: UUID) :
        PaymentCalculatorException("Duplicate payer: $id")
    public data class UnsupportedPaymentMode(public val mode: SplitType) :
        PaymentCalculatorException("Unsupported payment mode: $mode")
    public data object ExactAmountsRequired : PaymentCalculatorException("Exact amounts are required.")
    public data class MissingAmount(public val id: UUID) :
        PaymentCalculatorException("Missing amount for payer: $id")
    public data class ExtraAmount(public val id: UUID) :
        PaymentCalculatorException("Amount supplied for non-payer: $id")
    public data class InvalidPrecision(public val currency: String, public val maximumFractionDigits: Int) :
        PaymentCalculatorException("Amount exceeds $currency precision.")
    public data class AmountsDoNotSum(public val expected: BigDecimal, public val actual: BigDecimal) :
        PaymentCalculatorException("Amounts do not sum to total.")
}

public object PaymentCalculator {
    public fun calculate(
        totalAmount: BigDecimal,
        currency: String,
        payers: List<UUID>,
        paymentMode: SplitType,
        exactAmounts: Map<UUID, BigDecimal>? = null,
    ): List<Payment> {
        if (paymentMode !in setOf(SplitType.EQUAL, SplitType.EXACT)) {
            throw PaymentCalculatorException.UnsupportedPaymentMode(paymentMode)
        }
        return try {
            SplitCalculator.calculate(
                totalAmount = totalAmount,
                currency = currency,
                participants = payers,
                splitType = paymentMode,
                exactAmounts = exactAmounts,
            ).map { Payment(it.participantId, it.amountOwed, paymentMode) }
        } catch (error: SplitCalculatorException) {
            throw map(error)
        }
    }

    private fun map(error: SplitCalculatorException): PaymentCalculatorException = when (error) {
        SplitCalculatorException.EmptyParticipants -> PaymentCalculatorException.EmptyPayers
        is SplitCalculatorException.DuplicateParticipant -> PaymentCalculatorException.DuplicatePayer(error.id)
        is SplitCalculatorException.UnsupportedSplitType ->
            PaymentCalculatorException.UnsupportedPaymentMode(error.type)
        SplitCalculatorException.ExactAmountsRequired -> PaymentCalculatorException.ExactAmountsRequired
        is SplitCalculatorException.MissingAmount -> PaymentCalculatorException.MissingAmount(error.id)
        is SplitCalculatorException.ExtraAmount -> PaymentCalculatorException.ExtraAmount(error.id)
        is SplitCalculatorException.InvalidPrecision ->
            PaymentCalculatorException.InvalidPrecision(error.currency, error.maximumFractionDigits)
        is SplitCalculatorException.AmountsDoNotSum ->
            PaymentCalculatorException.AmountsDoNotSum(error.expected, error.actual)
        SplitCalculatorException.SharesRequired,
        is SplitCalculatorException.MissingShare,
        is SplitCalculatorException.ExtraShare,
        is SplitCalculatorException.NonPositiveShare,
        -> PaymentCalculatorException.UnsupportedPaymentMode(SplitType.SHARES)
        SplitCalculatorException.PercentagesRequired,
        is SplitCalculatorException.MissingPercentage,
        is SplitCalculatorException.ExtraPercentage,
        is SplitCalculatorException.NonPositivePercentage,
        is SplitCalculatorException.PercentagesDoNotSumTo100,
        -> PaymentCalculatorException.UnsupportedPaymentMode(SplitType.PERCENTAGE)
    }
}
