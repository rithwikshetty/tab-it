package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.nio.file.Path
import java.time.Instant
import java.util.UUID
import kotlin.io.path.exists
import kotlin.io.path.readText
import kotlin.test.Test
import kotlin.test.assertEquals

class ParityFixtureTest {
    private val fixture = JsonValue.parse(
        generateSequence(Path.of("").toAbsolutePath()) { it.parent }
            .map { it.resolve("contracts/domain/parity-v1.json") }
            .first(Path::exists)
            .readText(),
    )

    @Test
    fun equalSplitsMatchSharedFixture() {
        fixture["splitCases"].arrayValue.forEach { item ->
            val participants = item["participants"].arrayValue.map { UUID.fromString(it.stringValue) }
            val actual = SplitCalculator.calculate(
                BigDecimal(item["total"].stringValue),
                item["currency"].stringValue,
                participants,
                SplitType.EQUAL,
            )
            assertEquals(
                item["expected"].arrayValue.map { BigDecimal(it.stringValue) },
                actual.map(ExpenseSplit::amountOwed),
                item["name"].stringValue,
            )
        }
    }

    @Test
    fun balancesMatchSharedFixture() {
        fixture["balanceCases"].arrayValue.forEach { item ->
            val timestamp = Instant.parse("2026-01-01T12:00:00Z")
            val trip = UUID.fromString("10000000-0000-0000-0000-000000000001")
            val payments = item["payments"].arrayValue.map {
                Payment(
                    UUID.fromString(it["person"].stringValue),
                    BigDecimal(it["amount"].stringValue),
                    SplitType.EXACT,
                )
            }
            val splits = item["splits"].arrayValue.map {
                ExpenseSplit(
                    UUID.fromString(it["person"].stringValue),
                    BigDecimal(it["amount"].stringValue),
                    SplitType.EXACT,
                )
            }
            val expense = Expense(
                tripId = trip,
                amount = Money.parse(item["total"].stringValue, item["currency"].stringValue),
                expenseDate = timestamp,
                payments = payments,
                splits = splits,
                createdBy = payments.first().payerId,
                createdAt = timestamp,
                updatedAt = timestamp,
            )
            val positive = BalanceEngine.compute(listOf(expense), emptyList()).filter { it.amount > BigDecimal.ZERO }
            val expected = item["expected"].arrayValue.map {
                Triple(
                    UUID.fromString(it["for"].stringValue) to UUID.fromString(it["with"].stringValue),
                    item["currency"].stringValue,
                    BigDecimal(it["amount"].stringValue).stripTrailingZeros().toPlainString(),
                )
            }
            assertEquals(
                expected,
                positive.map {
                    Triple(
                        it.forUser to it.withUser,
                        it.currency,
                        it.amount.stripTrailingZeros().toPlainString(),
                    )
                },
                item["name"].stringValue,
            )
        }
    }

    @Test
    fun tripStatesMatchSharedFixture() {
        val first = UUID.fromString("00000000-0000-0000-0000-000000000001")
        val second = UUID.fromString("00000000-0000-0000-0000-000000000002")
        fixture["tripStateCases"].arrayValue.forEach { item ->
            val balances = if (item["hasBalance"].booleanValue) {
                listOf(UserBalance(first, second, "GBP", BigDecimal.ONE))
            } else {
                emptyList()
            }
            val actual = TripStateDeriver.derive(
                balances,
                Instant.parse(item["lastActivity"].stringValue),
                Instant.parse(item["now"].stringValue),
            )
            assertEquals(
                item["expected"].stringValue,
                actual.name.lowercase(),
                item["name"].stringValue,
            )
        }
    }
}
