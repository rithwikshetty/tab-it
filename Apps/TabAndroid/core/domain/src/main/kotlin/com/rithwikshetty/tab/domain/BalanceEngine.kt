package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.math.RoundingMode
import java.util.UUID
import kotlin.ConsistentCopyVisibility

public data class UserBalance(
    public val forUser: UUID,
    public val withUser: UUID,
    public val currency: String,
    public val amount: BigDecimal,
)

public object BalanceEngine {
    public fun compute(expenses: List<Expense>, settlements: List<Settlement>): List<UserBalance> {
        val canonical = mutableMapOf<PairKey, MutableMap<String, BigDecimal>>()
        expenses.filter { it.deletedAt == null }.forEach { expense ->
            distributePairs(expense).forEach { debt ->
                val key = PairKey.of(debt.creditor, debt.debtor)
                val signed = key.signedAmount(debt.debtor, debt.amount)
                canonical.getOrPut(key, ::mutableMapOf).merge(
                    expense.amount.currency,
                    signed,
                    BigDecimal::add,
                )
            }
        }
        settlements.filter { it.deletedAt == null }.forEach { settlement ->
            val key = PairKey.of(settlement.fromUserId, settlement.toUserId)
            val signed = key.signedAmount(settlement.fromUserId, settlement.amount.amount)
            canonical.getOrPut(key, ::mutableMapOf).merge(
                settlement.amount.currency,
                signed.negate(),
                BigDecimal::add,
            )
        }
        return buildList {
            canonical.keys.sortedWith(compareBy<PairKey> { it.low.toString() }.thenBy { it.high.toString() })
                .forEach { key ->
                    canonical.getValue(key).toSortedMap().forEach { (currency, amount) ->
                        if (amount.compareTo(BigDecimal.ZERO) != 0) {
                            add(UserBalance(key.low, key.high, currency, amount))
                            add(UserBalance(key.high, key.low, currency, amount.negate()))
                        }
                    }
                }
        }
    }

    internal fun distributePairs(expense: Expense): List<PairDebt> {
        val nets = mutableMapOf<UUID, BigDecimal>()
        expense.payments.forEach { nets.merge(it.payerId, it.amountPaid, BigDecimal::add) }
        expense.splits.forEach { nets.merge(it.participantId, it.amountOwed.negate(), BigDecimal::add) }
        val creditors = nets.mapNotNull { (id, net) ->
            if (net > BigDecimal.ZERO) Position(id, net) else null
        }.sortedBy { it.id.toString() }
        val debtors = nets.mapNotNull { (id, net) ->
            if (net < BigDecimal.ZERO) Position(id, net.negate()) else null
        }.sortedBy { it.id.toString() }
        val totalSurplus = creditors.fold(BigDecimal.ZERO) { value, item -> value + item.amount }
        if (totalSurplus <= BigDecimal.ZERO) return emptyList()
        val multiplier = CurrencyCatalog.minorUnitMultiplier(expense.amount.currency)
        return buildList {
            debtors.forEach { debtor ->
                val floors = MutableList(creditors.size) { BigDecimal.ZERO }
                val fractions = mutableListOf<Pair<Int, BigDecimal>>()
                creditors.forEachIndexed { index, creditor ->
                    val rawMinor = debtor.amount.multiply(creditor.amount).multiply(multiplier)
                        .divide(totalSurplus, 24, RoundingMode.HALF_UP)
                    val floor = rawMinor.setScale(0, RoundingMode.DOWN)
                    floors[index] = floor
                    fractions += index to rawMinor.subtract(floor)
                }
                var leftover = debtor.amount.multiply(multiplier).setScale(0, RoundingMode.DOWN)
                    .subtract(floors.fold(BigDecimal.ZERO, BigDecimal::add)).intValueExact()
                val order = fractions.sortedWith(
                    compareByDescending<Pair<Int, BigDecimal>> { it.second }
                        .thenBy { creditors[it.first].id.toString() },
                )
                var next = 0
                while (leftover > 0) {
                    val index = order[next % order.size].first
                    floors[index] = floors[index] + BigDecimal.ONE
                    leftover--
                    next++
                }
                creditors.forEachIndexed { index, creditor ->
                    if (floors[index].compareTo(BigDecimal.ZERO) != 0) {
                        add(PairDebt(creditor.id, debtor.id, floors[index].divide(multiplier)))
                    }
                }
            }
        }
    }

    internal data class PairDebt(
        val creditor: UUID,
        val debtor: UUID,
        val amount: BigDecimal,
    )

    private data class Position(val id: UUID, val amount: BigDecimal)

    @ConsistentCopyVisibility
    private data class PairKey private constructor(val low: UUID, val high: UUID) {
        companion object {
            fun of(a: UUID, b: UUID): PairKey = PairKey(
                if (a.toString() < b.toString()) a else b,
                if (a.toString() < b.toString()) b else a,
            )
        }

        fun signedAmount(debtor: UUID, amount: BigDecimal): BigDecimal =
            if (debtor == high) amount else amount.negate()
    }
}
