package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.util.UUID

public data class SimplifiedDebt(
    public val fromUser: UUID,
    public val toUser: UUID,
    public val currency: String,
    public val amount: BigDecimal,
)

public object DebtSimplifier {
    public fun simplify(balances: List<UserBalance>): List<SimplifiedDebt> {
        val byCurrency = mutableMapOf<String, MutableMap<UUID, BigDecimal>>()
        balances.filter {
            it.forUser.toString() < it.withUser.toString() && it.amount.compareTo(BigDecimal.ZERO) != 0
        }.forEach { balance ->
            val positions = byCurrency.getOrPut(balance.currency, ::mutableMapOf)
            positions.merge(balance.forUser, balance.amount, BigDecimal::add)
            positions.merge(balance.withUser, balance.amount.negate(), BigDecimal::add)
        }
        return buildList {
            byCurrency.toSortedMap().forEach { (currency, values) ->
                val creditors = values.mapNotNull { (id, amount) ->
                    if (amount > BigDecimal.ZERO) MutablePosition(id, amount) else null
                }.toMutableList()
                val debtors = values.mapNotNull { (id, amount) ->
                    if (amount < BigDecimal.ZERO) MutablePosition(id, amount.negate()) else null
                }.toMutableList()
                while (creditors.isNotEmpty() && debtors.isNotEmpty()) {
                    creditors.sortWith(positionOrder)
                    debtors.sortWith(positionOrder)
                    val amount = creditors.first().amount.min(debtors.first().amount)
                    if (amount <= BigDecimal.ZERO) break
                    add(SimplifiedDebt(debtors.first().id, creditors.first().id, currency, amount))
                    creditors.first().amount -= amount
                    debtors.first().amount -= amount
                    creditors.removeAll { it.amount.compareTo(BigDecimal.ZERO) == 0 }
                    debtors.removeAll { it.amount.compareTo(BigDecimal.ZERO) == 0 }
                }
            }
        }
    }

    private data class MutablePosition(val id: UUID, var amount: BigDecimal)
    private val positionOrder: Comparator<MutablePosition> =
        compareByDescending<MutablePosition> { it.amount }.thenBy { it.id.toString() }
}
