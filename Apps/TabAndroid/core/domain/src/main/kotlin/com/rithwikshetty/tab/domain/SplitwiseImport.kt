package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import java.time.DateTimeException
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.ZonedDateTime

public data class ImportShare(
    public val person: String,
    public val amount: BigDecimal,
)

public sealed interface SplitwiseRow {
    public data class Expense(
        public val date: ZonedDateTime,
        public val description: String,
        public val category: String,
        public val currency: String,
        public val total: BigDecimal,
        public val payments: List<ImportShare>,
        public val splits: List<ImportShare>,
    ) : SplitwiseRow

    public data class Settlement(
        public val date: ZonedDateTime,
        public val description: String,
        public val currency: String,
        public val amount: BigDecimal,
        public val from: String,
        public val to: String,
    ) : SplitwiseRow
}

public data class ImportWarning(
    public val line: Int,
    public val message: String,
)

public data class SplitwiseImportResult(
    public val people: List<String>,
    public val rows: List<SplitwiseRow>,
    public val warnings: List<ImportWarning>,
) {
    public val expenses: List<SplitwiseRow.Expense>
        get() = rows.filterIsInstance<SplitwiseRow.Expense>()
    public val settlements: List<SplitwiseRow.Settlement>
        get() = rows.filterIsInstance<SplitwiseRow.Settlement>()
}

public sealed class SplitwiseParseException(message: String) : IllegalArgumentException(message) {
    public data object Empty : SplitwiseParseException("The import is empty.")
    public data object MissingHeader : SplitwiseParseException("The Splitwise header is missing.")
    public data class UnexpectedHeader(public val found: List<String>) :
        SplitwiseParseException("Unexpected Splitwise header: $found")
    public data object NoPeople : SplitwiseParseException("The import contains no people.")
}

public object SplitwiseImport {
    private val leadingColumns = listOf("Date", "Description", "Category", "Cost", "Currency")
    private const val settlementCategory = "Payment"
    private const val settleAllDescription = "Settle all balances"
    private const val totalBalanceDescription = "Total balance"

    public fun parse(text: String): SplitwiseImportResult {
        val input = text.removePrefix("\uFEFF")
        val records = splitRecords(input)
        val header = records.firstOrNull() ?: throw SplitwiseParseException.Empty
        val leading = header.fields.take(leadingColumns.size).map(String::trim)
        if (leading.size != leadingColumns.size) throw SplitwiseParseException.MissingHeader
        if (leading.zip(leadingColumns).any { (found, expected) -> !found.equals(expected, true) }) {
            throw SplitwiseParseException.UnexpectedHeader(leading)
        }
        val columnNames = header.fields.drop(leadingColumns.size).map(String::trim).filter(String::isNotEmpty)
        val people = columnNames.distinct()
        if (people.isEmpty()) throw SplitwiseParseException.NoPeople
        val rows = mutableListOf<SplitwiseRow>()
        val warnings = mutableListOf<ImportWarning>()
        if (people.size != columnNames.size) {
            warnings += ImportWarning(header.line, "Duplicate person names in the header are merged into one person.")
        }
        records.drop(1).forEach { record ->
            parseRow(record, columnNames, people, rows, warnings)
        }
        return SplitwiseImportResult(people, rows, warnings)
    }

    private fun parseRow(
        record: CsvRecord,
        columnNames: List<String>,
        people: List<String>,
        rows: MutableList<SplitwiseRow>,
        warnings: MutableList<ImportWarning>,
    ) {
        if (record.fields.all { it.isBlank() }) return
        val dateText = record.field(0)
        val description = record.field(1)
        val category = record.field(2)
        val costText = record.field(3)
        val currency = CurrencyCatalog.normalizedCode(record.field(4))
        if (description.equals(totalBalanceDescription, true)) return
        val date = parseDate(dateText)
        if (date == null) {
            warnings += ImportWarning(record.line, "Unreadable date \"$dateText\"; row skipped.")
            return
        }
        val total = parseDecimal(costText)
        if (total == null || total <= BigDecimal.ZERO) {
            warnings += ImportWarning(record.line, "Unreadable or zero amount; row skipped.")
            return
        }
        val netByName = mutableMapOf<String, BigDecimal>()
        columnNames.forEachIndexed { index, name ->
            val raw = record.field(leadingColumns.size + index)
            if (raw.isEmpty()) return@forEachIndexed
            val value = parseDecimal(raw)
            if (value == null) {
                warnings += ImportWarning(record.line, "Unreadable amount \"$raw\"; row skipped.")
                return
            }
            netByName.merge(name, value, BigDecimal::add)
        }
        val nets = people.mapNotNull { person ->
            val net = netByName[person] ?: BigDecimal.ZERO
            if (net.compareTo(BigDecimal.ZERO) == 0) null else PersonNet(person, net)
        }
        val isSettlement = category.equals(settlementCategory, true) ||
            description.equals(settleAllDescription, true)
        if (isSettlement) {
            val positives = nets.filter { it.net > BigDecimal.ZERO }
            val negatives = nets.filter { it.net < BigDecimal.ZERO }
            if (positives.size == 1 && negatives.size == 1) {
                rows += SplitwiseRow.Settlement(
                    date,
                    description,
                    currency,
                    total,
                    positives.single().person,
                    negatives.single().person,
                )
                return
            }
            warnings += ImportWarning(
                record.line,
                "Payment row \"$description\" wasn't a two-person transfer; imported as an expense.",
            )
        }
        val reconstructed = reconstruct(total, currency, nets, people, record.line, warnings) ?: return
        rows += SplitwiseRow.Expense(
            date,
            description,
            category,
            currency,
            total,
            reconstructed.first,
            reconstructed.second,
        )
    }

    private fun reconstruct(
        total: BigDecimal,
        currency: String,
        nets: List<PersonNet>,
        people: List<String>,
        line: Int,
        warnings: MutableList<ImportWarning>,
    ): Pair<List<ImportShare>, List<ImportShare>>? {
        val multiplier = CurrencyCatalog.minorUnitMultiplier(currency)
        val costMinor = minorUnits(total, multiplier)
        val netMinor = nets.map { MinorNet(it.person, minorUnits(it.net, multiplier)) }
            .filter { it.net != BigInteger.ZERO }
        val debtors = netMinor.filter { it.net < BigInteger.ZERO }
        val payers = netMinor.filter { it.net > BigInteger.ZERO }
        val owed = mutableListOf<MinorShare>()
        val paid = mutableListOf<MinorShare>()
        if (payers.isEmpty()) {
            if (debtors.isEmpty()) {
                val solo = people.firstOrNull() ?: return null
                warnings += ImportWarning(line, "Row has no balances; recorded as paid in full by $solo.")
                return listOf(ImportShare(solo, total)) to listOf(ImportShare(solo, total))
            }
            warnings += ImportWarning(line, "Row doesn't balance (no payer); skipped.")
            return null
        }
        val debtorOwedTotal = debtors.fold(BigInteger.ZERO) { value, net -> value - net.net }
        val payersOwedTotal = costMinor - debtorOwedTotal
        if (payersOwedTotal < BigInteger.ZERO) {
            warnings += ImportWarning(line, "Row doesn't balance (debts exceed the amount); skipped.")
            return null
        }
        debtors.forEach { owed += MinorShare(it.person, it.net.negate()) }
        val sortedPayers = payers.sortedBy(MinorNet::person)
        val totalSurplus = sortedPayers.fold(BigInteger.ZERO) { value, payer -> value + payer.net }
        val floors = MutableList(sortedPayers.size) { BigInteger.ZERO }
        val fractions = mutableListOf<Pair<Int, BigDecimal>>()
        sortedPayers.forEachIndexed { index, payer ->
            val raw = BigDecimal(payersOwedTotal).multiply(BigDecimal(payer.net))
                .divide(BigDecimal(totalSurplus), 24, RoundingMode.HALF_UP)
            val floor = raw.setScale(0, RoundingMode.DOWN).toBigIntegerExact()
            floors[index] = floor
            fractions += index to raw.subtract(BigDecimal(floor))
        }
        var leftover = payersOwedTotal - floors.fold(BigInteger.ZERO, BigInteger::add)
        val order = fractions.sortedWith(
            compareByDescending<Pair<Int, BigDecimal>> { it.second }
                .thenBy { sortedPayers[it.first].person },
        )
        var next = 0
        while (leftover > BigInteger.ZERO) {
            val index = order[next % order.size].first
            floors[index] += BigInteger.ONE
            leftover -= BigInteger.ONE
            next++
        }
        sortedPayers.forEachIndexed { index, payer ->
            if (floors[index] > BigInteger.ZERO) owed += MinorShare(payer.person, floors[index])
            paid += MinorShare(payer.person, payer.net + floors[index])
        }
        val paidSum = paid.fold(BigInteger.ZERO) { value, share -> value + share.amount }
        val drift = costMinor - paidSum
        if (drift != BigInteger.ZERO) {
            val largestIndex = paid.indices.maxByOrNull { paid[it].amount }
            if (largestIndex != null) {
                paid[largestIndex] = paid[largestIndex].copy(amount = paid[largestIndex].amount + drift)
                if (drift.abs() > BigInteger.TWO) {
                    warnings += ImportWarning(
                        line,
                        "Row's amounts didn't sum cleanly; adjusted by ${fromMinor(drift, multiplier)} to balance.",
                    )
                }
            }
        }
        val valid = paid.fold(BigInteger.ZERO) { value, share -> value + share.amount } == costMinor &&
            owed.fold(BigInteger.ZERO) { value, share -> value + share.amount } == costMinor &&
            paid.all { it.amount >= BigInteger.ZERO } &&
            owed.all { it.amount >= BigInteger.ZERO }
        if (!valid) {
            warnings += ImportWarning(line, "Row's amounts don't balance; skipped.")
            return null
        }
        return paid.filter { it.amount > BigInteger.ZERO }
            .map { ImportShare(it.person, fromMinor(it.amount, multiplier)) } to
            owed.filter { it.amount > BigInteger.ZERO }
                .map { ImportShare(it.person, fromMinor(it.amount, multiplier)) }
    }

    internal fun splitRecords(text: String): List<CsvRecord> =
        text.replace("\r\n", "\n").replace('\r', '\n').split('\n').mapIndexedNotNull { index, line ->
            if (line.isEmpty()) null else CsvRecord(index + 1, parseFields(line))
        }

    internal fun parseFields(line: String): List<String> {
        val fields = mutableListOf<String>()
        val current = StringBuilder()
        var inQuotes = false
        var index = 0
        while (index < line.length) {
            val character = line[index]
            if (inQuotes) {
                if (character == '"' && index + 1 < line.length && line[index + 1] == '"') {
                    current.append('"')
                    index++
                } else if (character == '"') {
                    inQuotes = false
                } else {
                    current.append(character)
                }
            } else {
                when (character) {
                    '"' -> inQuotes = true
                    ',' -> {
                        fields += current.toString()
                        current.clear()
                    }
                    else -> current.append(character)
                }
            }
            index++
        }
        fields += current.toString()
        return fields
    }

    internal fun parseDecimal(value: String): BigDecimal? {
        val cleaned = value.trim()
        if (!Regex("[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)").matches(cleaned)) return null
        return cleaned.toBigDecimalOrNull()
    }

    internal fun parseDate(value: String): ZonedDateTime? = try {
        LocalDate.parse(value.trim()).atTime(12, 0).atZone(ZoneOffset.UTC)
    } catch (_: DateTimeException) {
        null
    }

    private fun minorUnits(amount: BigDecimal, multiplier: BigDecimal): BigInteger =
        amount.multiply(multiplier).setScale(0, RoundingMode.HALF_UP).toBigIntegerExact()

    private fun fromMinor(amount: BigInteger, multiplier: BigDecimal): BigDecimal =
        BigDecimal(amount).divide(multiplier)

    internal data class CsvRecord(val line: Int, val fields: List<String>) {
        fun field(index: Int): String = fields.getOrElse(index) { "" }.trim()
    }

    private data class PersonNet(val person: String, val net: BigDecimal)
    private data class MinorNet(val person: String, val net: BigInteger)
    private data class MinorShare(val person: String, val amount: BigInteger)
}
