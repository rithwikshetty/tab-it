package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import kotlin.ConsistentCopyVisibility

@ConsistentCopyVisibility
public data class Money private constructor(
    public val amount: BigDecimal,
    public val currency: String,
) {
    public operator fun plus(other: Money): Money {
        require(currency == other.currency) {
            "Cannot add different currencies."
        }
        return Money(amount.add(other.amount), currency)
    }

    public companion object {
        private val CurrencyPattern: Regex = Regex("[A-Z]{3}")

        public fun parse(amount: String, currency: String): Money {
            require(CurrencyPattern.matches(currency)) {
                "Currency must be a three-letter uppercase code."
            }
            return Money(BigDecimal(amount), currency)
        }
    }
}
