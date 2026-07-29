package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs

class SplitAndPaymentCalculatorTest {
    private val one = UUID.fromString("00000000-0000-0000-0000-000000000001")
    private val two = UUID.fromString("00000000-0000-0000-0000-000000000002")
    private val three = UUID.fromString("00000000-0000-0000-0000-000000000003")

    @Test
    fun exactSplitRequiresCompleteExactSum() {
        val result = SplitCalculator.calculate(
            BigDecimal("10.00"),
            "GBP",
            listOf(one, two),
            SplitType.EXACT,
            exactAmounts = mapOf(one to BigDecimal("4.25"), two to BigDecimal("5.75")),
        )
        assertEquals(listOf(BigDecimal("4.25"), BigDecimal("5.75")), result.map { it.amountOwed })
        assertIs<SplitCalculatorException.AmountsDoNotSum>(
            assertFailsWith {
                SplitCalculator.calculate(
                    BigDecimal("10.00"),
                    "GBP",
                    listOf(one, two),
                    SplitType.EXACT,
                    exactAmounts = mapOf(one to BigDecimal("4.24"), two to BigDecimal("5.75")),
                )
            },
        )
    }

    @Test
    fun sharesUseLargestRemainderAndCarryWeights() {
        val result = SplitCalculator.calculate(
            BigDecimal("10.00"),
            "GBP",
            listOf(one, two, three),
            SplitType.SHARES,
            shares = mapOf(one to BigDecimal("1"), two to BigDecimal("2"), three to BigDecimal("3")),
        )
        assertEquals(listOf("1.67", "3.33", "5.00"), result.map { it.amountOwed.setScale(2).toPlainString() })
        assertEquals(listOf("1", "2", "3"), result.map { it.shareUnits!!.toPlainString() })
    }

    @Test
    fun percentagesMustBePositiveCompleteAndExactlyOneHundred() {
        val result = SplitCalculator.calculate(
            BigDecimal("0.05"),
            "GBP",
            listOf(two, one),
            SplitType.PERCENTAGE,
            percentages = mapOf(one to BigDecimal("50"), two to BigDecimal("50")),
        )
        assertEquals(listOf(BigDecimal("0.02"), BigDecimal("0.03")), result.map { it.amountOwed })
        assertIs<SplitCalculatorException.PercentagesDoNotSumTo100>(
            assertFailsWith {
                SplitCalculator.calculate(
                    BigDecimal("1.00"),
                    "GBP",
                    listOf(one, two),
                    SplitType.PERCENTAGE,
                    percentages = mapOf(one to BigDecimal("60"), two to BigDecimal("39")),
                )
            },
        )
    }

    @Test
    fun invalidPrecisionDuplicateAndMissingInputsAreTypedErrors() {
        assertIs<SplitCalculatorException.InvalidPrecision>(
            assertFailsWith {
                SplitCalculator.calculate(BigDecimal("1.001"), "GBP", listOf(one), SplitType.EQUAL)
            },
        )
        assertIs<SplitCalculatorException.DuplicateParticipant>(
            assertFailsWith {
                SplitCalculator.calculate(BigDecimal("1.00"), "GBP", listOf(one, one), SplitType.EQUAL)
            },
        )
        assertIs<SplitCalculatorException.MissingShare>(
            assertFailsWith {
                SplitCalculator.calculate(
                    BigDecimal("1.00"),
                    "GBP",
                    listOf(one, two),
                    SplitType.SHARES,
                    shares = mapOf(one to BigDecimal.ONE),
                )
            },
        )
    }

    @Test
    fun equalPercentageSeedSumsExactlyAndUsesUuidOrder() {
        val result = SplitCalculator.equalPercentages(listOf(three, one, two))
        assertEquals(BigDecimal("100.00"), result.values.fold(BigDecimal.ZERO, BigDecimal::add))
        assertEquals(BigDecimal("33.34"), result.getValue(one))
    }

    @Test
    fun paymentsMirrorSplitRulesButExposePaymentErrors() {
        val result = PaymentCalculator.calculate(
            BigDecimal("10.00"),
            "GBP",
            listOf(three, one, two),
            SplitType.EQUAL,
        )
        assertEquals(listOf("3.33", "3.34", "3.33"), result.map { it.amountPaid.setScale(2).toPlainString() })
        assertIs<PaymentCalculatorException.EmptyPayers>(
            assertFailsWith {
                PaymentCalculator.calculate(BigDecimal.ONE, "GBP", emptyList(), SplitType.EQUAL)
            },
        )
        assertIs<PaymentCalculatorException.UnsupportedPaymentMode>(
            assertFailsWith {
                PaymentCalculator.calculate(BigDecimal.ONE, "GBP", listOf(one), SplitType.SHARES)
            },
        )
    }
}
