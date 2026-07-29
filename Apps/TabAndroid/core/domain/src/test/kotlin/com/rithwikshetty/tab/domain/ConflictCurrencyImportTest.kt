package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ConflictCurrencyImportTest {
    private val lowWrite = UUID.fromString("00000000-0000-0000-0000-000000000001")
    private val highWrite = UUID.fromString("00000000-0000-0000-0000-000000000002")
    private val old = Instant.parse("2026-01-01T00:00:00Z")
    private val recent = Instant.parse("2026-01-02T00:00:00Z")

    @Test
    fun conflictResolutionIsLastWriteWinsWithDeleteWins() {
        val edit = Versioned("edit", recent, null, highWrite)
        val delete = Versioned("deleted", old, old, lowWrite)
        assertEquals(delete, ConflictResolver.resolve(edit, delete))
        val tieLow = Versioned("low", recent, null, lowWrite)
        val tieHigh = Versioned("high", recent, null, highWrite)
        assertEquals(tieHigh, ConflictResolver.resolve(tieLow, tieHigh))
    }

    @Test
    fun pullMergeHonorsDirtyStateAndConvergence() {
        val local = Versioned(Unit, recent, null, highWrite)
        val remote = Versioned(Unit, old, null, lowWrite)
        assertEquals(MergeDecision.APPLY_REMOTE, ConflictResolver.merge(local, false, remote))
        assertEquals(MergeDecision.KEEP_LOCAL, ConflictResolver.merge(local, true, remote))
        assertEquals(
            MergeDecision.KEEP_LOCAL,
            ConflictResolver.merge(local, true, remote.copy(writeId = highWrite)),
        )
    }

    @Test
    fun currencyPrecisionAndMidpointRoundingMatchContract() {
        assertEquals(0, CurrencyCatalog.fractionDigits("JPY"))
        assertEquals(3, CurrencyCatalog.fractionDigits("KWD"))
        assertTrue(CurrencyCatalog.hasValidPrecision(BigDecimal("1.23"), "GBP"))
        assertTrue(!CurrencyCatalog.hasValidPrecision(BigDecimal("1.234"), "GBP"))
        assertEquals(BigDecimal("1.24"), CurrencyCatalog.normalizedAmount(BigDecimal("1.235"), "GBP"))
        assertEquals(BigDecimal("-1.24"), CurrencyCatalog.normalizedAmount(BigDecimal("-1.235"), "GBP"))
        assertNull(CurrencyCatalog.metadata("ZZZ"))
    }

    @Test
    fun splitwiseParsesExpensesSettlementQuotesAndUtcNoon() {
        val csv = """
            Date,Description,Category,Cost,Currency,Alice,Bob
            2026-01-01,"Dinner, drinks",Food,10.00,GBP,5.00,-5.00
            2026-01-02,Repayment,Payment,3.00,GBP,3.00,-3.00
        """.trimIndent()
        val result = SplitwiseImport.parse(csv)
        assertEquals(listOf("Alice", "Bob"), result.people)
        assertEquals("Dinner, drinks", result.expenses.single().description)
        assertEquals(12, result.expenses.single().date.hour)
        assertEquals("Alice", result.settlements.single().from)
        assertEquals("Bob", result.settlements.single().to)
        assertTrue(result.warnings.isEmpty())
    }

    @Test
    fun splitwiseHandlesBomDuplicateNamesAndMalformedRowsSafely() {
        val csv = "\uFEFF" + """
            Date,Description,Category,Cost,Currency,Alice,Alice
            2026-01-01,Dinner,Food,10.00,GBP,3.00,2.00
            nope,Bad,Food,4.00,GBP,2.00,-2.00
            2026-01-03,Grouped,Food,"1,000.00",GBP,500.00,-500.00
        """.trimIndent()
        val result = SplitwiseImport.parse(csv)
        assertEquals(listOf("Alice"), result.people)
        assertEquals(1, result.expenses.size)
        assertEquals(4, result.warnings.size)
    }

    @Test
    fun splitwiseRejectsMissingContractHeader() {
        assertIs<SplitwiseParseException.UnexpectedHeader>(
            assertFailsWith {
                SplitwiseImport.parse("When,What,Category,Cost,Currency,Alice")
            },
        )
    }
}
