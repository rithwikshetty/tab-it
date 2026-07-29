package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LedgerRulesTest {
    private val one = UUID.fromString("00000000-0000-0000-0000-000000000001")
    private val two = UUID.fromString("00000000-0000-0000-0000-000000000002")
    private val three = UUID.fromString("00000000-0000-0000-0000-000000000003")
    private val trip = UUID.fromString("10000000-0000-0000-0000-000000000001")
    private val now = Instant.parse("2026-01-01T12:00:00Z")

    @Test
    fun multiPayerBalanceIsMinorUnitExactAndMirrored() {
        val balances = BalanceEngine.compute(
            listOf(
                expense(
                    "10.00",
                    listOf(one to "5.00", two to "5.00"),
                    listOf(one to "3.33", two to "3.33", three to "3.34"),
                ),
            ),
            emptyList(),
        )
        assertEquals(4, balances.size)
        assertEquals(
            0,
            balances.fold(BigDecimal.ZERO) { value, item -> value + item.amount }.compareTo(BigDecimal.ZERO),
        )
        assertTrue(balances.all { CurrencyCatalog.hasValidPrecision(it.amount, it.currency) })
    }

    @Test
    fun settlementReducesThenFlipsDebtAndDeletedRowsAreIgnored() {
        val base = expense("10.00", listOf(one to "10.00"), listOf(two to "10.00"))
        val settlement = Settlement(
            tripId = trip,
            fromUserId = two,
            toUserId = one,
            amount = Money.parse("12.00", "GBP"),
            settledAt = now,
            createdBy = two,
            createdAt = now,
            updatedAt = now,
        )
        val flipped = BalanceEngine.compute(listOf(base), listOf(settlement))
        assertEquals(BigDecimal("-2.00"), flipped.first { it.forUser == one }.amount)
        assertTrue(BalanceEngine.compute(listOf(base.copy(deletedAt = now)), listOf(settlement.copy(deletedAt = now))).isEmpty())
    }

    @Test
    fun debtSimplificationPreservesNetPositionsAndCurrencies() {
        val balances = listOf(
            UserBalance(one, two, "GBP", BigDecimal("10")),
            UserBalance(two, one, "GBP", BigDecimal("-10")),
            UserBalance(two, three, "GBP", BigDecimal("10")),
            UserBalance(three, two, "GBP", BigDecimal("-10")),
            UserBalance(one, three, "EUR", BigDecimal("2")),
            UserBalance(three, one, "EUR", BigDecimal("-2")),
        )
        assertEquals(
            listOf(
                SimplifiedDebt(three, one, "EUR", BigDecimal("2")),
                SimplifiedDebt(three, one, "GBP", BigDecimal("10")),
            ),
            DebtSimplifier.simplify(balances),
        )
    }

    @Test
    fun analyticsPartitionCurrencyAndExcludeDeletedExpenses() {
        val category = UUID.fromString("20000000-0000-0000-0000-000000000001")
        val first = expense("10.00", listOf(one to "10.00"), listOf(two to "10.00")).copy(categoryId = category)
        val deleted = expense("7.00", listOf(two to "7.00"), listOf(one to "7.00")).copy(deletedAt = now)
        val jpy = expense("100", listOf(one to "100"), listOf(three to "100"), "JPY")
        val summary = TripAnalytics.summarize(listOf(first, deleted, jpy))
        assertEquals(listOf("GBP", "JPY"), summary.map { it.currency })
        assertEquals(BigDecimal("10.00"), summary.first().total)
        assertEquals(category, summary.first().perCategory.single().categoryId)
    }

    @Test
    fun overallBalancesCollapseContainerIdsToClaimIdentity() {
        val otherTripPerson = UUID.fromString("00000000-0000-0000-0000-000000000004")
        val userOne = ClaimIdentity.User(UUID.fromString("90000000-0000-0000-0000-000000000001"))
        val userTwo = ClaimIdentity.Email("friend@example.com")
        val containers = listOf(
            ContainerBalances(trip, mirrored(one, two, "10.00")),
            ContainerBalances(UUID.randomUUID(), mirrored(otherTripPerson, two, "-4.00")),
        )
        val result = OverallBalanceAggregator.aggregate(
            containers,
            mapOf(one to userOne, otherTripPerson to userOne, two to userTwo),
        )
        assertEquals(2, result.size)
        assertEquals(BigDecimal("-6.00"), result.first { it.forIdentity == userTwo }.amount)
    }

    private fun mirrored(creditor: UUID, debtor: UUID, amount: String): List<UserBalance> {
        val value = BigDecimal(amount)
        return listOf(
            UserBalance(creditor, debtor, "GBP", value),
            UserBalance(debtor, creditor, "GBP", value.negate()),
        )
    }

    private fun expense(
        amount: String,
        payments: List<Pair<UUID, String>>,
        splits: List<Pair<UUID, String>>,
        currency: String = "GBP",
    ): Expense = Expense(
        tripId = trip,
        amount = Money.parse(amount, currency),
        expenseDate = now,
        payments = payments.map { Payment(it.first, BigDecimal(it.second), SplitType.EXACT) },
        splits = splits.map { ExpenseSplit(it.first, BigDecimal(it.second), SplitType.EXACT) },
        createdBy = one,
        createdAt = now,
        updatedAt = now,
    )
}
