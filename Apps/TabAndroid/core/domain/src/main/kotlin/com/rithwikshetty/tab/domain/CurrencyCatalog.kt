package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.Normalizer
import java.util.Currency
import java.util.Locale

public data class CurrencyMetadata(
    public val code: String,
    public val symbol: String,
    public val name: String,
    public val fractionDigits: Int,
)

public object CurrencyCatalog {
    public const val DEFAULT_CODE: String = "INR"
    public const val MAXIMUM_SUPPORTED_FRACTION_DIGITS: Int = 8

    private val codePattern: Regex = Regex("[A-Z]{3}")
    private val symbolClaimPriority: List<String> = listOf(
        "USD", "EUR", "JPY", "GBP", "CNY", "AUD", "CAD", "CHF", "HKD", "SGD",
        "SEK", "KRW", "NOK", "NZD", "INR", "MXN", "TWD", "ZAR", "BRL", "DKK",
    )
    private val currenciesByCode: Map<String, Currency> =
        Currency.getAvailableCurrencies().associateBy(Currency::getCurrencyCode)
    public val supportedCodes: List<String> = currenciesByCode.keys.sorted()
    private val symbolsByCode: Map<String, String> = createUniqueSymbols()
    public val supported: List<CurrencyMetadata> = supportedCodes.map(::metadataForNormalizedCode)

    public fun normalizedCode(code: String): String = code.trim().uppercase(Locale.ROOT)

    public fun isCurrencyCode(code: String): Boolean = codePattern.matches(code)

    public fun isSupported(code: String): Boolean = currenciesByCode.containsKey(normalizedCode(code))

    public fun metadata(code: String): CurrencyMetadata? =
        supported.firstOrNull { it.code == normalizedCode(code) }

    public fun displayMetadata(code: String): CurrencyMetadata =
        metadata(code) ?: metadataForNormalizedCode(normalizedCode(code))

    public fun fractionDigits(code: String): Int = displayMetadata(code).fractionDigits

    public fun minorUnitMultiplier(code: String): BigDecimal =
        BigDecimal.TEN.pow(fractionDigits(code))

    public fun hasValidPrecision(amount: BigDecimal, currency: String): Boolean =
        amount.multiply(minorUnitMultiplier(currency)).stripTrailingZeros().scale() <= 0

    public fun normalizedAmount(amount: BigDecimal, currency: String): BigDecimal =
        amount.setScale(fractionDigits(currency), RoundingMode.HALF_UP)

    public fun search(query: String): List<CurrencyMetadata> {
        val normalizedQuery = fold(query.trim())
        if (normalizedQuery.isEmpty()) return supported
        return supported.filter { currency ->
            fold(currency.code).contains(normalizedQuery) ||
                fold(currency.symbol).contains(normalizedQuery) ||
                fold(currency.name).contains(normalizedQuery)
        }
    }

    private fun metadataForNormalizedCode(code: String): CurrencyMetadata {
        val currency = currenciesByCode[code]
        val digits = currency?.defaultFractionDigits
            ?.coerceIn(0, MAXIMUM_SUPPORTED_FRACTION_DIGITS)
            ?: 2
        return CurrencyMetadata(
            code = code,
            symbol = symbolsByCode[code] ?: code,
            name = currency?.displayName ?: code,
            fractionDigits = digits,
        )
    }

    private fun createUniqueSymbols(): Map<String, String> {
        val rank = symbolClaimPriority.withIndex().associate { it.value to it.index }
        val claimed = mutableSetOf<String>()
        val result = mutableMapOf<String, String>()
        val ordered = supportedCodes.sortedWith(
            compareBy<String> { rank[it] ?: Int.MAX_VALUE }.thenBy { it },
        )
        for (code in ordered) {
            val currency = currenciesByCode.getValue(code)
            val candidates = buildSet {
                add(cleanSymbol(currency.getSymbol(Locale.US)))
                for (locale in Locale.getAvailableLocales()) {
                    if (runCatching { Currency.getInstance(locale) }.getOrNull() == currency) {
                        add(cleanSymbol(currency.getSymbol(locale)))
                    }
                }
                add(code)
            }.filter(String::isNotEmpty).sortedWith(
                compareBy<String> { it.uppercase(Locale.ROOT) == code }
                    .thenBy(String::length)
                    .thenBy { it },
            )
            val symbol = candidates.firstOrNull { claimKey(it) !in claimed } ?: code
            claimed += claimKey(symbol)
            result[code] = symbol
        }
        return result
    }

    private fun cleanSymbol(value: String): String =
        value.replace("\u200E", "").replace("\u200F", "").replace("\u061C", "").trim()

    private fun claimKey(symbol: String): String =
        Normalizer.normalize(symbol, Normalizer.Form.NFKC).uppercase(Locale.ROOT)

    private fun fold(value: String): String =
        Normalizer.normalize(value, Normalizer.Form.NFD)
            .replace(Regex("\\p{M}+"), "")
            .lowercase(Locale.getDefault())
}
