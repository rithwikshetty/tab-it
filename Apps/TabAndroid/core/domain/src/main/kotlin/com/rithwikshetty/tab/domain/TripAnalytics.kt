package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.util.UUID

public data class PersonSpend(
    public val personId: UUID,
    public val paid: BigDecimal,
    public val share: BigDecimal,
)

public data class CategorySpend(
    public val categoryId: UUID?,
    public val total: BigDecimal,
)

public data class TripSpendSummary(
    public val currency: String,
    public val total: BigDecimal,
    public val perPerson: List<PersonSpend>,
    public val perCategory: List<CategorySpend>,
)

public object TripAnalytics {
    public fun summarize(expenses: List<Expense>): List<TripSpendSummary> =
        expenses.filter { it.deletedAt == null }.groupBy { it.amount.currency }.toSortedMap()
            .map { (currency, group) ->
                val paid = mutableMapOf<UUID, BigDecimal>()
                val share = mutableMapOf<UUID, BigDecimal>()
                val category = mutableMapOf<UUID?, BigDecimal>()
                group.forEach { expense ->
                    expense.payments.forEach {
                        paid.merge(it.payerId, it.amountPaid, BigDecimal::add)
                    }
                    expense.splits.forEach {
                        share.merge(it.participantId, it.amountOwed, BigDecimal::add)
                    }
                    category.merge(expense.categoryId, expense.amount.amount, BigDecimal::add)
                }
                TripSpendSummary(
                    currency = currency,
                    total = group.fold(BigDecimal.ZERO) { value, expense -> value + expense.amount.amount },
                    perPerson = (paid.keys + share.keys).map { id ->
                        PersonSpend(id, paid[id] ?: BigDecimal.ZERO, share[id] ?: BigDecimal.ZERO)
                    }.sortedWith(
                        compareByDescending<PersonSpend> { it.share }.thenByDescending { it.personId.toString() },
                    ),
                    perCategory = category.map { CategorySpend(it.key, it.value) }.sortedWith { a, b ->
                        val amountOrder = b.total.compareTo(a.total)
                        when {
                            amountOrder != 0 -> amountOrder
                            a.categoryId == null && b.categoryId != null -> 1
                            a.categoryId != null && b.categoryId == null -> -1
                            else -> (a.categoryId?.toString() ?: "").compareTo(b.categoryId?.toString() ?: "")
                        }
                    },
                )
            }
}
