package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.math.RoundingMode
import java.util.UUID

public sealed class SplitCalculatorException(message: String) : IllegalArgumentException(message) {
    public data object EmptyParticipants : SplitCalculatorException("Participants cannot be empty.")
    public data class DuplicateParticipant(public val id: UUID) :
        SplitCalculatorException("Duplicate participant: $id")
    public data class UnsupportedSplitType(public val type: SplitType) :
        SplitCalculatorException("Unsupported split type: $type")
    public data object ExactAmountsRequired : SplitCalculatorException("Exact amounts are required.")
    public data class MissingAmount(public val id: UUID) :
        SplitCalculatorException("Missing amount for participant: $id")
    public data class ExtraAmount(public val id: UUID) :
        SplitCalculatorException("Amount supplied for non-participant: $id")
    public data class InvalidPrecision(public val currency: String, public val maximumFractionDigits: Int) :
        SplitCalculatorException("Amount exceeds $currency precision.")
    public data class AmountsDoNotSum(public val expected: BigDecimal, public val actual: BigDecimal) :
        SplitCalculatorException("Amounts do not sum to total.")
    public data object SharesRequired : SplitCalculatorException("Shares are required.")
    public data class MissingShare(public val id: UUID) :
        SplitCalculatorException("Missing share for participant: $id")
    public data class ExtraShare(public val id: UUID) :
        SplitCalculatorException("Share supplied for non-participant: $id")
    public data class NonPositiveShare(public val id: UUID) :
        SplitCalculatorException("Share must be positive: $id")
    public data object PercentagesRequired : SplitCalculatorException("Percentages are required.")
    public data class MissingPercentage(public val id: UUID) :
        SplitCalculatorException("Missing percentage for participant: $id")
    public data class ExtraPercentage(public val id: UUID) :
        SplitCalculatorException("Percentage supplied for non-participant: $id")
    public data class NonPositivePercentage(public val id: UUID) :
        SplitCalculatorException("Percentage must be positive: $id")
    public data class PercentagesDoNotSumTo100(public val actual: BigDecimal) :
        SplitCalculatorException("Percentages do not sum to 100.")
}

public object SplitCalculator {
    public fun calculate(
        totalAmount: BigDecimal,
        currency: String,
        participants: List<UUID>,
        splitType: SplitType,
        exactAmounts: Map<UUID, BigDecimal>? = null,
        shares: Map<UUID, BigDecimal>? = null,
        percentages: Map<UUID, BigDecimal>? = null,
    ): List<ExpenseSplit> {
        if (participants.isEmpty()) throw SplitCalculatorException.EmptyParticipants
        participants.groupingBy { it }.eachCount().entries.firstOrNull { it.value > 1 }?.let {
            throw SplitCalculatorException.DuplicateParticipant(it.key)
        }
        validatePrecision(totalAmount, currency)

        return when (splitType) {
            SplitType.EQUAL -> calculateEqual(totalAmount, currency, participants)
            SplitType.EXACT -> calculateExact(
                totalAmount,
                currency,
                participants,
                exactAmounts ?: throw SplitCalculatorException.ExactAmountsRequired,
            )
            SplitType.SHARES -> calculateWeighted(
                totalAmount,
                currency,
                participants,
                shares ?: throw SplitCalculatorException.SharesRequired,
                SplitType.SHARES,
            )
            SplitType.PERCENTAGE -> calculateWeighted(
                totalAmount,
                currency,
                participants,
                percentages ?: throw SplitCalculatorException.PercentagesRequired,
                SplitType.PERCENTAGE,
            )
            SplitType.ADJUSTMENT -> throw SplitCalculatorException.UnsupportedSplitType(splitType)
        }
    }

    public fun equalPercentages(participants: List<UUID>): Map<UUID, BigDecimal> {
        if (participants.isEmpty()) return emptyMap()
        val base = 10_000 / participants.size
        val remainder = 10_000 % participants.size
        return participants.sortedBy(UUID::toString).mapIndexed { index, id ->
            id to BigDecimal(base + if (index < remainder) 1 else 0).movePointLeft(2)
        }.toMap()
    }

    private fun calculateEqual(
        total: BigDecimal,
        currency: String,
        participants: List<UUID>,
    ): List<ExpenseSplit> {
        val multiplier = CurrencyCatalog.minorUnitMultiplier(currency)
        val totalMinor = total.multiply(multiplier).setScale(0, RoundingMode.HALF_UP).toBigIntegerExact()
        val count = participants.size.toBigInteger()
        val base = totalMinor.divide(count)
        val remainder = totalMinor.remainder(count).toInt()
        val bonusIds = participants.sortedBy(UUID::toString).take(remainder).toSet()
        return participants.map { id ->
            val minor = base + if (id in bonusIds) java.math.BigInteger.ONE else java.math.BigInteger.ZERO
            ExpenseSplit(id, BigDecimal(minor).divide(multiplier), SplitType.EQUAL)
        }
    }

    private fun calculateExact(
        total: BigDecimal,
        currency: String,
        participants: List<UUID>,
        amounts: Map<UUID, BigDecimal>,
    ): List<ExpenseSplit> {
        val participantSet = participants.toSet()
        amounts.keys.firstOrNull { it !in participantSet }?.let {
            throw SplitCalculatorException.ExtraAmount(it)
        }
        participants.firstOrNull { it !in amounts }?.let {
            throw SplitCalculatorException.MissingAmount(it)
        }
        amounts.values.forEach { validatePrecision(it, currency) }
        val sum = amounts.values.fold(BigDecimal.ZERO, BigDecimal::add)
        if (sum.compareTo(total) != 0) throw SplitCalculatorException.AmountsDoNotSum(total, sum)
        return participants.map { ExpenseSplit(it, amounts.getValue(it), SplitType.EXACT) }
    }

    private fun calculateWeighted(
        total: BigDecimal,
        currency: String,
        participants: List<UUID>,
        weights: Map<UUID, BigDecimal>,
        type: SplitType,
    ): List<ExpenseSplit> {
        val participantSet = participants.toSet()
        weights.keys.firstOrNull { it !in participantSet }?.let {
            if (type == SplitType.SHARES) throw SplitCalculatorException.ExtraShare(it)
            throw SplitCalculatorException.ExtraPercentage(it)
        }
        participants.firstOrNull { it !in weights }?.let {
            if (type == SplitType.SHARES) throw SplitCalculatorException.MissingShare(it)
            throw SplitCalculatorException.MissingPercentage(it)
        }
        participants.sortedBy(UUID::toString).firstOrNull {
            weights.getValue(it).compareTo(BigDecimal.ZERO) <= 0
        }?.let {
            if (type == SplitType.SHARES) throw SplitCalculatorException.NonPositiveShare(it)
            throw SplitCalculatorException.NonPositivePercentage(it)
        }
        if (type == SplitType.PERCENTAGE) {
            val sum = participants.fold(BigDecimal.ZERO) { value, id -> value + weights.getValue(id) }
            if (sum.compareTo(BigDecimal("100")) != 0) {
                throw SplitCalculatorException.PercentagesDoNotSumTo100(sum)
            }
        }
        val amounts = allocateProportionally(total, currency, participants, weights)
        return participants.map { id ->
            ExpenseSplit(
                participantId = id,
                amountOwed = amounts.getValue(id),
                splitType = type,
                shareUnits = weights[id].takeIf { type == SplitType.SHARES },
                percentage = weights[id].takeIf { type == SplitType.PERCENTAGE },
            )
        }
    }

    private fun allocateProportionally(
        total: BigDecimal,
        currency: String,
        participants: List<UUID>,
        weights: Map<UUID, BigDecimal>,
    ): Map<UUID, BigDecimal> {
        val multiplier = CurrencyCatalog.minorUnitMultiplier(currency)
        val totalMinor = total.multiply(multiplier).setScale(0, RoundingMode.HALF_UP)
        val weightSum = participants.fold(BigDecimal.ZERO) { value, id -> value + weights.getValue(id) }
        val floors = mutableMapOf<UUID, BigDecimal>()
        val fractions = mutableMapOf<UUID, BigDecimal>()
        participants.forEach { id ->
            val ideal = totalMinor.multiply(weights.getValue(id)).divide(weightSum, 24, RoundingMode.HALF_UP)
            val floor = ideal.setScale(0, RoundingMode.DOWN)
            floors[id] = floor
            fractions[id] = ideal - floor
        }
        var remaining = totalMinor.subtract(floors.values.fold(BigDecimal.ZERO, BigDecimal::add)).intValueExact()
        val order = participants.sortedWith(
            compareByDescending<UUID> { fractions.getValue(it) }.thenBy(UUID::toString),
        )
        for (id in order) {
            if (remaining <= 0) break
            floors[id] = floors.getValue(id) + BigDecimal.ONE
            remaining--
        }
        for (id in order.asReversed()) {
            if (remaining >= 0) break
            if (floors.getValue(id) > BigDecimal.ZERO) {
                floors[id] = floors.getValue(id) - BigDecimal.ONE
                remaining++
            }
        }
        return floors.mapValues { (_, minor) -> minor.divide(multiplier) }
    }

    private fun validatePrecision(amount: BigDecimal, currency: String) {
        if (!CurrencyCatalog.hasValidPrecision(amount, currency)) {
            throw SplitCalculatorException.InvalidPrecision(
                CurrencyCatalog.normalizedCode(currency),
                CurrencyCatalog.fractionDigits(currency),
            )
        }
    }
}
