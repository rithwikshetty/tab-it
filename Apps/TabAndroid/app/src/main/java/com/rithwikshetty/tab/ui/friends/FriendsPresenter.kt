package com.rithwikshetty.tab.ui.friends

import com.rithwikshetty.tab.data.LocalContainer
import com.rithwikshetty.tab.data.LocalLedgerSnapshot
import com.rithwikshetty.tab.data.LocalPerson
import com.rithwikshetty.tab.domain.BalanceEngine
import com.rithwikshetty.tab.domain.ClaimIdentity
import com.rithwikshetty.tab.domain.ContainerBalances
import com.rithwikshetty.tab.domain.DebtSimplifier
import com.rithwikshetty.tab.domain.OverallBalanceAggregator
import com.rithwikshetty.tab.domain.SimplifiedDebt
import com.rithwikshetty.tab.domain.UserBalance
import java.math.BigDecimal
import java.util.UUID

data class FriendAmountLine(
    val currency: String,
    val amount: BigDecimal,
)

data class FriendRow(
    val identity: ClaimIdentity,
    val displayName: String,
    val email: String?,
    val isPending: Boolean,
    val sourceSummary: String,
    val lines: List<FriendAmountLine>,
) {
    val isSettled: Boolean get() = lines.isEmpty()
}

data class FriendsOverallLine(
    val currency: String,
    val youAreOwed: BigDecimal,
    val youOwe: BigDecimal,
)

data class FriendsUiState(
    val overall: List<FriendsOverallLine> = emptyList(),
    val active: List<FriendRow> = emptyList(),
    val settled: List<FriendRow> = emptyList(),
    val knownPeople: List<FriendRow> = emptyList(),
    val details: Map<String, FriendDetail> = emptyMap(),
)

data class FriendSourceRow(
    val containerId: UUID,
    val sourceName: String,
    val currency: String,
    val amount: BigDecimal,
    val suggestion: SimplifiedDebt,
)

data class FriendDetail(
    val friend: FriendRow,
    val sources: List<FriendSourceRow>,
)

object FriendsPresenter {
    fun present(snapshot: LocalLedgerSnapshot, currentUserId: UUID): FriendsUiState {
        val me = ClaimIdentity.User(currentUserId)
        val peopleByTrip = snapshot.people
            .mapNotNull { person -> person.tripId?.let { it to person } }
            .groupBy({ it.first }, { it.second })
        val activeContainers = snapshot.containers.filter { container ->
            peopleByTrip[container.id].orEmpty().any { it.identity() == me }
        }
        val activeContainerIds = activeContainers.map(LocalContainer::id).toSet()
        val people = snapshot.people.filter { it.tripId in activeContainerIds }
        val identityMap = people.associate { it.id to it.identity() }
        val containers = activeContainers.map { container ->
            val balances = BalanceEngine.compute(
                expenses = snapshot.expenses.filter { it.tripId == container.id },
                settlements = snapshot.settlements.filter { it.tripId == container.id },
            )
            ContainerBalances(
                containerId = container.id,
                balances = DebtSimplifier.simplify(balances).flatMap { debt ->
                    listOf(
                        UserBalance(debt.toUser, debt.fromUser, debt.currency, debt.amount),
                        UserBalance(
                            debt.fromUser,
                            debt.toUser,
                            debt.currency,
                            debt.amount.negate(),
                        ),
                    )
                },
            )
        }
        val myBalances = OverallBalanceAggregator.aggregate(containers, identityMap)
            .filter { it.forIdentity == me }
        val claims = buildSet {
            people.mapTo(this, LocalPerson::identity)
            myBalances.mapTo(this) { it.withIdentity }
            remove(me)
        }
        val rows = claims.map { claim ->
            val matchingPeople = people.filter { it.identity() == claim }
            val lines = myBalances
                .filter { it.withIdentity == claim && it.amount.compareTo(BigDecimal.ZERO) != 0 }
                .sortedBy { it.currency }
                .map { FriendAmountLine(it.currency, it.amount) }
            FriendRow(
                identity = claim,
                displayName = matchingPeople.firstNotNullOfOrNull {
                    it.displayName.trim().ifEmpty { null }
                } ?: (claim as? ClaimIdentity.Email)?.email ?: "Member",
                email = matchingPeople.firstOrNull()?.email
                    ?: (claim as? ClaimIdentity.Email)?.email,
                isPending = claim is ClaimIdentity.Email,
                sourceSummary = sourceSummary(
                    containers = activeContainers,
                    peopleByTrip = peopleByTrip,
                    claim = claim,
                ),
                lines = lines,
            )
        }.sortedBy { it.displayName.lowercase() }
        val currencies = myBalances.map { it.currency }.toSortedSet()
        val overall = currencies.map { currency ->
            val values = myBalances.filter { it.currency == currency }.map { it.amount }
            FriendsOverallLine(
                currency = currency,
                youAreOwed = values.filter { it > BigDecimal.ZERO }
                    .fold(BigDecimal.ZERO, BigDecimal::add),
                youOwe = values.filter { it < BigDecimal.ZERO }
                    .fold(BigDecimal.ZERO) { total, value -> total + value.abs() },
            )
        }
        val containerById = activeContainers.associateBy(LocalContainer::id)
        val details = rows.associate { row ->
            val sources = OverallBalanceAggregator.breakdown(
                containers = containers,
                identityMap = identityMap,
                forIdentity = me,
                withIdentity = row.identity,
            ).mapNotNull { source ->
                val members = peopleByTrip[source.containerId].orEmpty()
                val myPerson = members.firstOrNull { it.identity() == me } ?: return@mapNotNull null
                val friendPerson = members.firstOrNull {
                    it.identity() == row.identity
                } ?: return@mapNotNull null
                val from = if (source.amount > BigDecimal.ZERO) {
                    friendPerson.id
                } else {
                    myPerson.id
                }
                val to = if (source.amount > BigDecimal.ZERO) {
                    myPerson.id
                } else {
                    friendPerson.id
                }
                val container = containerById[source.containerId] ?: return@mapNotNull null
                FriendSourceRow(
                    containerId = source.containerId,
                    sourceName = if (container.kind == "non_group") {
                        "Non-group"
                    } else {
                        container.name
                    },
                    currency = source.currency,
                    amount = source.amount,
                    suggestion = SimplifiedDebt(
                        fromUser = from,
                        toUser = to,
                        currency = source.currency,
                        amount = source.amount.abs(),
                    ),
                )
            }
            row.identity.canonicalKey to FriendDetail(row, sources)
        }
        return FriendsUiState(
            overall = overall,
            active = rows.filterNot(FriendRow::isSettled),
            settled = rows.filter(FriendRow::isSettled),
            knownPeople = rows.filter { it.email != null },
            details = details,
        )
    }

    private fun sourceSummary(
        containers: List<LocalContainer>,
        peopleByTrip: Map<UUID, List<LocalPerson>>,
        claim: ClaimIdentity,
    ): String {
        val shared = containers.filter { container ->
            peopleByTrip[container.id].orEmpty().any { it.identity() == claim }
        }
        val hasNonGroup = shared.any { it.kind == "non_group" }
        val tripNames = shared.filter { it.kind == "trip" }.map { it.name }
        return buildList {
            if (hasNonGroup) add("Non-group")
            when (tripNames.size) {
                1 -> add(tripNames.single())
                in 2..Int.MAX_VALUE -> add("${tripNames.size} trips")
            }
        }.joinToString(" + ")
    }
}

private fun LocalPerson.identity(): ClaimIdentity =
    ClaimIdentity.resolve(userId, email)
