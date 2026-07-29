package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.util.Locale
import java.util.UUID
import kotlin.ConsistentCopyVisibility

public sealed interface ClaimIdentity {
    public val canonicalKey: String

    public data class User(public val id: UUID) : ClaimIdentity {
        override val canonicalKey: String = "u:$id"
    }

    public data class Email(public val email: String) : ClaimIdentity {
        override val canonicalKey: String = "e:$email"
    }

    public companion object {
        public fun resolve(userId: UUID?, email: String): ClaimIdentity =
            userId?.let(::User) ?: Email(email.lowercase(Locale.ROOT))
    }
}

public data class ContainerBalances(
    public val containerId: UUID,
    public val balances: List<UserBalance>,
)

public data class OverallBalance(
    public val forIdentity: ClaimIdentity,
    public val withIdentity: ClaimIdentity,
    public val currency: String,
    public val amount: BigDecimal,
)

public data class SourceBalance(
    public val containerId: UUID,
    public val currency: String,
    public val amount: BigDecimal,
)

public object OverallBalanceAggregator {
    public fun aggregate(
        containers: List<ContainerBalances>,
        identityMap: Map<UUID, ClaimIdentity>,
    ): List<OverallBalance> {
        val canonical = mutableMapOf<IdentityPair, MutableMap<String, BigDecimal>>()
        containers.forEach { container ->
            container.balances.forEach rowLoop@{ row ->
                val first = identityMap[row.forUser] ?: return@rowLoop
                val second = identityMap[row.withUser] ?: return@rowLoop
                if (first == second) return@rowLoop
                val pair = IdentityPair.of(first, second)
                if (first != pair.low) return@rowLoop
                canonical.getOrPut(pair, ::mutableMapOf).merge(row.currency, row.amount, BigDecimal::add)
            }
        }
        return buildList {
            canonical.keys.sortedWith(
                compareBy<IdentityPair> { it.low.canonicalKey }.thenBy { it.high.canonicalKey },
            ).forEach { pair ->
                canonical.getValue(pair).toSortedMap().forEach { (currency, amount) ->
                    if (amount.compareTo(BigDecimal.ZERO) != 0) {
                        add(OverallBalance(pair.low, pair.high, currency, amount))
                        add(OverallBalance(pair.high, pair.low, currency, amount.negate()))
                    }
                }
            }
        }
    }

    public fun breakdown(
        containers: List<ContainerBalances>,
        identityMap: Map<UUID, ClaimIdentity>,
        forIdentity: ClaimIdentity,
        withIdentity: ClaimIdentity,
    ): List<SourceBalance> {
        if (forIdentity == withIdentity) return emptyList()
        return containers.flatMap { container ->
            val totals = mutableMapOf<String, BigDecimal>()
            container.balances.forEach rowLoop@{ row ->
                val first = identityMap[row.forUser] ?: return@rowLoop
                val second = identityMap[row.withUser] ?: return@rowLoop
                if (first == forIdentity && second == withIdentity) {
                    totals.merge(row.currency, row.amount, BigDecimal::add)
                }
            }
            totals.filterValues { it.compareTo(BigDecimal.ZERO) != 0 }.map { (currency, amount) ->
                SourceBalance(container.containerId, currency, amount)
            }
        }.sortedWith(compareBy<SourceBalance> { it.containerId.toString() }.thenBy { it.currency })
    }

    @ConsistentCopyVisibility
    private data class IdentityPair private constructor(val low: ClaimIdentity, val high: ClaimIdentity) {
        companion object {
            fun of(a: ClaimIdentity, b: ClaimIdentity): IdentityPair = IdentityPair(
                if (a.canonicalKey < b.canonicalKey) a else b,
                if (a.canonicalKey < b.canonicalKey) b else a,
            )
        }
    }
}
