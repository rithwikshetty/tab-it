package com.rithwikshetty.tab

import com.rithwikshetty.tab.data.LocalCategory
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.ExpenseSplit
import com.rithwikshetty.tab.domain.Money
import com.rithwikshetty.tab.domain.Payment
import com.rithwikshetty.tab.domain.PaymentMethod
import com.rithwikshetty.tab.domain.Settlement
import com.rithwikshetty.tab.domain.SplitType
import com.rithwikshetty.tab.domain.SplitwiseImportResult
import com.rithwikshetty.tab.domain.SplitwiseRow
import com.rithwikshetty.tab.sync.AuthenticatedUser
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.first

class SplitwiseImportCoordinator(
    private val container: TabContainer,
) {
    suspend fun run(
        parsed: SplitwiseImportResult,
        tripName: String,
        selfPerson: String,
        user: AuthenticatedUser,
    ): UUID {
        val userId = UUID.fromString(user.id)
        val email = requireNotNull(user.email) { "A verified email is required to import." }
        val tripId = container.tripRepository.create(
            name = tripName,
            userId = userId,
            email = email,
            displayName = email.substringBefore("@"),
        )
        try {
            syncUntilSettled()
            val remote = checkNotNull(container.remoteGateway)
            val creator = container.tripRepository.observePeople(tripId).first()
                .single { it.userId == userId }
            val personIds = mutableMapOf(selfPerson to creator.id)
            parsed.people.filter { it != selfPerson }.forEach { name ->
                val id = UUID.randomUUID()
                remote.addTripPerson(
                    tripId = tripId.toString(),
                    email = "${id.toString().lowercase()}@users.tab",
                    displayName = name,
                    personId = id.toString(),
                )
                personIds[name] = id
            }
            syncOnce()
            val categories = container.tripRepository.observeCategories(tripId).first()
            val now = Instant.now()
            parsed.rows.forEach { row ->
                when (row) {
                    is SplitwiseRow.Expense -> container.expenseRepository.save(
                        Expense(
                            id = UUID.randomUUID(),
                            tripId = tripId,
                            amount = Money.parse(row.total.toPlainString(), row.currency),
                            categoryId = categoryId(row.category, categories),
                            description = row.description.ifBlank { "Imported expense" },
                            paymentMethod = PaymentMethod.CARD,
                            expenseDate = row.date.toInstant(),
                            payments = row.payments.map {
                                Payment(
                                    checkNotNull(personIds[it.person]),
                                    it.amount,
                                    SplitType.EXACT,
                                )
                            },
                            splits = row.splits.map {
                                ExpenseSplit(
                                    checkNotNull(personIds[it.person]),
                                    it.amount,
                                    SplitType.EXACT,
                                )
                            },
                            createdBy = userId,
                            createdAt = now,
                            updatedAt = now,
                        ),
                    )
                    is SplitwiseRow.Settlement -> container.settlementRepository.save(
                        Settlement(
                            id = UUID.randomUUID(),
                            tripId = tripId,
                            fromUserId = checkNotNull(personIds[row.from]),
                            toUserId = checkNotNull(personIds[row.to]),
                            amount = Money.parse(row.amount.toPlainString(), row.currency),
                            note = row.description.ifBlank { null },
                            settledAt = row.date.toInstant(),
                            createdBy = userId,
                            createdAt = now,
                            updatedAt = now,
                        ),
                    )
                }
            }
            syncUntilSettled()
            return tripId
        } catch (error: Exception) {
            runCatching {
                container.tripRepository.archive(tripId)
                syncUntilSettled()
            }
            throw error
        }
    }

    private suspend fun syncUntilSettled() {
        repeat(MAX_SYNC_BATCHES) {
            syncOnce()
            if (!container.tripRepository.hasPendingWork()) return
        }
        error("The import produced too many pending batches.")
    }

    private suspend fun syncOnce() {
        val report = checkNotNull(container.syncEngine).syncOnce()
        check(report.pushFailures == 0 && report.pullCompleted) {
            report.errorMessage ?: "Import synchronization failed."
        }
    }

    private fun categoryId(name: String, categories: List<LocalCategory>): UUID? {
        val target = when (name.trim().lowercase()) {
            "food and drink", "dining out", "dining", "groceries", "restaurant", "drinks" ->
                "food & drink"
            "transportation", "taxi", "car", "gas/fuel", "fuel", "bus/train", "plane",
            "parking", "transport" -> "transport"
            "hotel", "rent", "accommodation", "lodging", "hostel", "airbnb" -> "lodging"
            "entertainment", "games", "movies", "music", "sports", "activities" -> "activities"
            "shopping", "clothing", "electronics", "gifts" -> "shopping"
            else -> "other"
        }
        return categories.firstOrNull { it.name.lowercase() == target }?.id
    }

    private companion object {
        const val MAX_SYNC_BATCHES: Int = 100
    }
}
