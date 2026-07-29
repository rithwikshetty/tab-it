package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class MoneyTest {
    @Test
    fun addsExactDecimalAmountsInTheSameCurrency() {
        val total = Money.parse("0.10", "GBP") + Money.parse("0.20", "GBP")

        assertEquals(BigDecimal("0.30"), total.amount)
        assertEquals("GBP", total.currency)
    }

    @Test
    fun refusesToMixCurrencies() {
        assertFailsWith<IllegalArgumentException> {
            Money.parse("10.00", "GBP") + Money.parse("10.00", "EUR")
        }
    }
}
