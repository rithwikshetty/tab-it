package com.rithwikshetty.tab.data

import androidx.room.withTransaction
import com.rithwikshetty.tab.data.local.ExpenseEntity
import com.rithwikshetty.tab.data.local.ExpensePaymentEntity
import com.rithwikshetty.tab.data.local.ExpenseSplitEntity
import com.rithwikshetty.tab.data.local.ExpenseWithLedger
import com.rithwikshetty.tab.data.local.OutboxEntity
import com.rithwikshetty.tab.data.local.ProfileEntity
import com.rithwikshetty.tab.data.local.ReceiptDraftEntity
import com.rithwikshetty.tab.data.local.SettlementEntity
import com.rithwikshetty.tab.data.local.SyncStamp
import com.rithwikshetty.tab.data.local.TabDatabase
import com.rithwikshetty.tab.data.local.TripEntity
import com.rithwikshetty.tab.data.local.TripPersonEntity
import com.rithwikshetty.tab.data.local.CategoryEntity
import com.rithwikshetty.tab.data.local.ActivityEntity
import com.rithwikshetty.tab.data.local.TripMutePreferenceEntity
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.ExpenseSplit
import com.rithwikshetty.tab.domain.CurrencyCatalog
import com.rithwikshetty.tab.domain.Money
import com.rithwikshetty.tab.domain.Payment
import com.rithwikshetty.tab.domain.PaymentMethod
import com.rithwikshetty.tab.domain.Settlement
import com.rithwikshetty.tab.domain.SplitType
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

public data class LocalTripSummary(
    public val id: UUID,
    public val name: String,
    public val lastActivityAt: Instant,
)

public data class LocalPerson(
    public val id: UUID,
    public val userId: UUID?,
    public val email: String,
    public val displayName: String,
    public val hasJoined: Boolean,
    public val tripId: UUID? = null,
    public val joinedAt: Instant? = null,
)

public data class LocalActivity(
    public val id: UUID,
    public val tripId: UUID,
    public val actorId: UUID,
    public val action: String,
    public val entityType: String,
    public val entityId: UUID,
    public val timestamp: Instant,
    public val snapshotJson: String?,
)

public data class LocalActivityState(
    public val items: List<LocalActivity> = emptyList(),
    public val mutedTripIds: Set<UUID> = emptySet(),
    public val lastSeenAt: Instant? = null,
)

public data class LocalCategory(
    public val id: UUID,
    public val name: String,
    public val icon: String,
    public val isDefault: Boolean,
)

public data class LocalContainer(
    public val id: UUID,
    public val name: String,
    public val kind: String,
    public val memberSignature: String?,
)

public data class LocalLedgerSnapshot(
    public val containers: List<LocalContainer> = emptyList(),
    public val people: List<LocalPerson> = emptyList(),
    public val expenses: List<Expense> = emptyList(),
    public val settlements: List<Settlement> = emptyList(),
)

public class LocalTripRepository(
    private val database: TabDatabase,
) {
    public fun observeTrips(): Flow<List<LocalTripSummary>> =
        database.trips().observeActiveTrips().map { rows -> rows.map(TripEntity::toSummary) }

    public fun observeTrip(id: UUID): Flow<LocalTripSummary?> =
        database.trips().observeTrip(id.toString()).map { it?.toSummary() }

    public fun observePeople(id: UUID): Flow<List<LocalPerson>> =
        database.trips().observeActivePeople(id.toString()).map { people ->
            people.map(TripPersonEntity::toLocalPerson)
        }

    public fun observeCategories(id: UUID): Flow<List<LocalCategory>> =
        database.trips().observeCategories(id.toString()).map { categories ->
            categories.map(CategoryEntity::toLocalCategory)
        }

    public suspend fun create(
        name: String,
        userId: UUID,
        email: String,
        displayName: String,
        now: Instant = Instant.now(),
        tripId: UUID = UUID.randomUUID(),
        personId: UUID = UUID.randomUUID(),
        writeId: UUID = UUID.randomUUID(),
    ): UUID {
        val cleanName = name.trim()
        val cleanEmail = email.trim().lowercase(Locale.ROOT)
        require(cleanName.isNotEmpty()) { "Trip name is required." }
        require(cleanEmail.contains("@")) { "A verified email is required." }
        val stamp = SyncStamp(
            updatedAt = now.toString(),
            deletedAt = null,
            writeId = writeId.toString(),
            isDirty = true,
        )
        val trip = TripEntity(
            id = tripId.toString(),
            name = cleanName,
            kind = "trip",
            memberSignature = null,
            createdBy = userId.toString(),
            lastActivityAt = now.toString(),
            createdAt = now.toString(),
            sync = stamp,
        )
        val person = TripPersonEntity(
            id = personId.toString(),
            tripId = trip.id,
            userId = userId.toString(),
            email = cleanEmail,
            displayName = displayName.trim().ifEmpty { cleanEmail.substringBefore("@") },
            invitedBy = userId.toString(),
            joinedAt = now.toString(),
            removedAt = null,
            createdAt = now.toString(),
            sync = stamp.copy(isDirty = false),
        )
        database.withTransaction {
            if (database.profiles().find(userId.toString()) == null) {
                database.profiles().upsert(
                    ProfileEntity(
                        id = userId.toString(),
                        displayName = person.displayName,
                        avatarUrl = null,
                        activityLastSeenAt = null,
                        createdAt = now.toString(),
                        sync = stamp.copy(isDirty = false),
                    ),
                )
            }
            database.trips().upsert(trip)
            database.trips().upsertPeople(listOf(person))
            database.outbox().enqueue(
                OutboxEntity(
                    entityType = "trip",
                    entityId = trip.id,
                    operation = "create",
                    writeId = stamp.writeId,
                    createdAt = now.toString(),
                ),
            )
        }
        return tripId
    }

    public suspend fun rename(
        id: UUID,
        name: String,
        now: Instant = Instant.now(),
        writeId: UUID = UUID.randomUUID(),
    ) {
        val cleanName = name.trim()
        require(cleanName.isNotEmpty()) { "Trip name is required." }
        database.withTransaction {
            check(
                database.trips().rename(
                    id.toString(),
                    cleanName,
                    now.toString(),
                    writeId.toString(),
                ) == 1,
            ) { "Trip not found." }
            database.outbox().enqueue(
                OutboxEntity(
                    entityType = "trip",
                    entityId = id.toString(),
                    operation = "upsert",
                    writeId = writeId.toString(),
                    createdAt = now.toString(),
                ),
            )
        }
    }

    public suspend fun archive(
        id: UUID,
        now: Instant = Instant.now(),
        writeId: UUID = UUID.randomUUID(),
    ) {
        database.withTransaction {
            check(
                database.trips().softDelete(id.toString(), now.toString(), writeId.toString()) == 1,
            ) { "Trip not found." }
            database.outbox().enqueue(
                OutboxEntity(
                    entityType = "trip",
                    entityId = id.toString(),
                    operation = "delete",
                    writeId = writeId.toString(),
                    createdAt = now.toString(),
                ),
            )
        }
    }

    public suspend fun clearAccountData() {
        withContext(Dispatchers.IO) {
            database.clearAllTables()
        }
    }
}

public class LocalExpenseRepository(
    private val database: TabDatabase,
) {
    public fun observeExpenses(tripId: UUID): Flow<List<Expense>> =
        database.expenses().observeActiveForTrip(tripId.toString()).map { rows ->
            rows.map(ExpenseWithLedger::toDomain)
        }

    public fun observeExpense(id: UUID): Flow<Expense?> =
        database.expenses().observeAggregate(id.toString()).map { it?.toDomain() }

    public suspend fun find(id: UUID): Expense? =
        database.expenses().findAggregate(id.toString())?.toDomain()

    public suspend fun findReceiptLocalUri(id: UUID): String? =
        database.expenses().findReceiptDraft(id.toString())?.localUri

    public suspend fun save(
        expense: Expense,
        writeId: UUID = UUID.randomUUID(),
        receiptLocalUri: String? = null,
    ) {
        require(expense.description?.isNotBlank() == true) {
            "An expense description is required."
        }
        require(expense.amount.amount.signum() > 0) { "Expense amount must be positive." }
        require(CurrencyCatalog.hasValidPrecision(expense.amount.amount, expense.amount.currency)) {
            "Expense amount exceeds the currency's minor-unit precision."
        }
        require(expense.payments.isNotEmpty()) { "At least one payment is required." }
        require(expense.splits.isNotEmpty()) { "At least one split is required." }
        val paymentTotal = expense.payments.fold(java.math.BigDecimal.ZERO) { value, item ->
            value + item.amountPaid
        }
        val splitTotal = expense.splits.fold(java.math.BigDecimal.ZERO) { value, item ->
            value + item.amountOwed
        }
        require(paymentTotal.compareTo(expense.amount.amount) == 0) { "Payments must equal the expense total." }
        require(splitTotal.compareTo(expense.amount.amount) == 0) { "Splits must equal the expense total." }

        val stamp = SyncStamp(
            updatedAt = expense.updatedAt.toString(),
            deletedAt = expense.deletedAt?.toString(),
            writeId = writeId.toString(),
            isDirty = true,
        )
        val entity = expense.toEntity(stamp)
        database.withTransaction {
            database.expenses().upsertExpense(entity)
            database.expenses().deletePayments(entity.id)
            database.expenses().deleteSplits(entity.id)
            database.expenses().upsertPayments(expense.payments.map { it.toEntity(entity, stamp) })
            database.expenses().upsertSplits(expense.splits.map { it.toEntity(entity, stamp) })
            if (receiptLocalUri != null) {
                database.expenses().upsertReceiptDraft(
                    ReceiptDraftEntity(
                        expenseId = entity.id,
                        localUri = receiptLocalUri,
                        remotePath = expense.receiptStoragePath,
                        uploadState = "pending",
                        updatedAt = expense.updatedAt.toString(),
                    ),
                )
            }
            database.outbox().enqueue(
                OutboxEntity(
                    entityType = "expense",
                    entityId = entity.id,
                    operation = if (expense.deletedAt == null) "upsert" else "delete",
                    writeId = stamp.writeId,
                    createdAt = expense.updatedAt.toString(),
                ),
            )
            if (receiptLocalUri != null) {
                database.outbox().enqueue(
                    OutboxEntity(
                        entityType = "receipt",
                        entityId = entity.id,
                        operation = "upload",
                        writeId = stamp.writeId,
                        createdAt = expense.updatedAt.toString(),
                    ),
                )
            }
        }
    }

    public suspend fun softDelete(id: UUID, at: Instant, writeId: UUID = UUID.randomUUID()) {
        database.withTransaction {
            check(database.expenses().softDelete(id.toString(), at.toString(), writeId.toString()) == 1) {
                "Expense not found."
            }
            database.outbox().enqueue(
                OutboxEntity(
                    entityType = "expense",
                    entityId = id.toString(),
                    operation = "delete",
                    writeId = writeId.toString(),
                    createdAt = at.toString(),
                ),
            )
        }
    }
}

public class LocalSettlementRepository(
    private val database: TabDatabase,
) {
    public fun observeSettlements(tripId: UUID): Flow<List<Settlement>> =
        database.settlements().observeActiveForTrip(tripId.toString()).map { rows ->
            rows.map(SettlementEntity::toDomain)
        }

    public suspend fun find(id: UUID): Settlement? =
        database.settlements().find(id.toString())?.toDomain()

    public suspend fun save(
        settlement: Settlement,
        writeId: UUID = UUID.randomUUID(),
    ) {
        require(settlement.fromUserId != settlement.toUserId) {
            "A settlement needs two different people."
        }
        require(settlement.amount.amount > java.math.BigDecimal.ZERO) {
            "Settlement amount must be positive."
        }
        require(
            CurrencyCatalog.hasValidPrecision(
                settlement.amount.amount,
                settlement.amount.currency,
            ),
        ) { "Settlement amount exceeds the currency's minor-unit precision." }
        val entity = settlement.toEntity(
            SyncStamp(
                updatedAt = settlement.updatedAt.toString(),
                deletedAt = settlement.deletedAt?.toString(),
                writeId = writeId.toString(),
                isDirty = true,
            ),
        )
        database.withTransaction {
            database.settlements().upsert(entity)
            database.outbox().enqueue(
                OutboxEntity(
                    entityType = "settlement",
                    entityId = entity.id,
                    operation = if (entity.sync.deletedAt == null) "upsert" else "delete",
                    writeId = entity.sync.writeId,
                    createdAt = entity.sync.updatedAt,
                ),
            )
        }
    }

    public suspend fun softDelete(
        id: UUID,
        at: Instant = Instant.now(),
        writeId: UUID = UUID.randomUUID(),
    ) {
        database.withTransaction {
            check(
                database.settlements().softDelete(
                    id.toString(),
                    at.toString(),
                    writeId.toString(),
                ) == 1,
            ) { "Settlement not found." }
            database.outbox().enqueue(
                OutboxEntity(
                    entityType = "settlement",
                    entityId = id.toString(),
                    operation = "delete",
                    writeId = writeId.toString(),
                    createdAt = at.toString(),
                ),
            )
        }
    }
}

public class LocalBalanceRepository(
    database: TabDatabase,
) {
    public val snapshot: Flow<LocalLedgerSnapshot> = combine(
        database.trips().observeActiveContainers(),
        database.trips().observeAllActivePeople(),
        database.expenses().observeAllActive(),
        database.settlements().observeAllActive(),
    ) { containers, people, expenses, settlements ->
        LocalLedgerSnapshot(
            containers = containers.map(TripEntity::toLocalContainer),
            people = people.map(TripPersonEntity::toLocalPerson),
            expenses = expenses.map(ExpenseWithLedger::toDomain),
            settlements = settlements.map(SettlementEntity::toDomain),
        )
    }
}

public class LocalActivityRepository(
    private val database: TabDatabase,
) {
    public fun observe(userId: UUID): Flow<LocalActivityState> = combine(
        database.activity().observeAll(),
        database.preferences().observeMutedTripIds(userId.toString()),
        database.profiles().observe(userId.toString()),
    ) { activity, muted, profile ->
        LocalActivityState(
            items = activity.map(ActivityEntity::toLocalActivity),
            mutedTripIds = muted.map(UUID::fromString).toSet(),
            lastSeenAt = profile?.activityLastSeenAt?.let(Instant::parse),
        )
    }

    public suspend fun markSeen(userId: UUID, seenAt: Instant = Instant.now()) {
        check(database.profiles().updateActivityLastSeen(userId.toString(), seenAt.toString()) == 1) {
            "Current profile is not available."
        }
    }

    public suspend fun setTripMuted(
        tripId: UUID,
        userId: UUID,
        muted: Boolean,
        now: Instant = Instant.now(),
        writeId: UUID = UUID.randomUUID(),
    ) {
        val entity = TripMutePreferenceEntity(
            tripId = tripId.toString(),
            userId = userId.toString(),
            mutedAt = now.toString(),
            sync = SyncStamp(
                updatedAt = now.toString(),
                deletedAt = if (muted) null else now.toString(),
                writeId = writeId.toString(),
                isDirty = true,
            ),
        )
        database.withTransaction {
            database.preferences().upsert(entity)
            database.outbox().enqueue(
                OutboxEntity(
                    entityType = "mute",
                    entityId = entity.tripId,
                    operation = if (muted) "upsert" else "delete",
                    writeId = entity.sync.writeId,
                    createdAt = now.toString(),
                ),
            )
        }
    }
}

private fun TripEntity.toSummary(): LocalTripSummary =
    LocalTripSummary(UUID.fromString(id), name, Instant.parse(lastActivityAt))

private fun TripPersonEntity.toLocalPerson(): LocalPerson =
    LocalPerson(
        id = UUID.fromString(id),
        userId = userId?.let(UUID::fromString),
        email = email,
        displayName = displayName,
        hasJoined = joinedAt != null,
        tripId = UUID.fromString(tripId),
        joinedAt = joinedAt?.let(Instant::parse),
    )

private fun ActivityEntity.toLocalActivity(): LocalActivity =
    LocalActivity(
        id = UUID.fromString(id),
        tripId = UUID.fromString(tripId),
        actorId = UUID.fromString(actorId),
        action = action,
        entityType = entityType,
        entityId = UUID.fromString(entityId),
        timestamp = Instant.parse(timestamp),
        snapshotJson = snapshotJson,
    )

private fun CategoryEntity.toLocalCategory(): LocalCategory =
    LocalCategory(UUID.fromString(id), name, icon, isDefault)

private fun TripEntity.toLocalContainer(): LocalContainer =
    LocalContainer(UUID.fromString(id), name, kind, memberSignature)

private fun Settlement.toEntity(stamp: SyncStamp): SettlementEntity =
    SettlementEntity(
        id = id.toString(),
        tripId = tripId.toString(),
        fromPersonId = fromUserId.toString(),
        toPersonId = toUserId.toString(),
        amountText = amount.amount.toPlainString(),
        currency = amount.currency,
        note = note,
        settledAt = settledAt.toString(),
        createdBy = createdBy.toString(),
        createdAt = createdAt.toString(),
        sync = stamp,
    )

private fun SettlementEntity.toDomain(): Settlement =
    Settlement(
        id = UUID.fromString(id),
        tripId = UUID.fromString(tripId),
        fromUserId = UUID.fromString(fromPersonId),
        toUserId = UUID.fromString(toPersonId),
        amount = Money.parse(amountText, currency),
        note = note,
        settledAt = Instant.parse(settledAt),
        createdBy = UUID.fromString(createdBy),
        createdAt = Instant.parse(createdAt),
        updatedAt = Instant.parse(sync.updatedAt),
        deletedAt = sync.deletedAt?.let(Instant::parse),
    )

private fun Expense.toEntity(stamp: SyncStamp): ExpenseEntity = ExpenseEntity(
    id = id.toString(),
    tripId = tripId.toString(),
    amountText = amount.amount.toPlainString(),
    currency = amount.currency,
    categoryId = categoryId?.toString(),
    description = requireNotNull(description),
    expenseDate = expenseDate.atZone(ZoneOffset.UTC).toLocalDate().toString(),
    receiptStoragePath = receiptStoragePath,
    paymentMethod = paymentMethod.name.lowercase(Locale.ROOT),
    createdBy = createdBy.toString(),
    lastEditedBy = null,
    createdAt = createdAt.toString(),
    sync = stamp,
)

private fun Payment.toEntity(expense: ExpenseEntity, stamp: SyncStamp): ExpensePaymentEntity =
    ExpensePaymentEntity(
        expenseId = expense.id,
        tripPersonId = payerId.toString(),
        amountPaidText = amountPaid.toPlainString(),
        paymentMode = paymentMode.name.lowercase(Locale.ROOT),
        createdAt = expense.createdAt,
        sync = stamp.copy(deletedAt = null),
    )

private fun ExpenseSplit.toEntity(expense: ExpenseEntity, stamp: SyncStamp): ExpenseSplitEntity =
    ExpenseSplitEntity(
        expenseId = expense.id,
        tripPersonId = participantId.toString(),
        amountOwedText = amountOwed.toPlainString(),
        splitType = splitType.name.lowercase(Locale.ROOT),
        shareUnitsText = shareUnits?.toPlainString(),
        percentageText = percentage?.toPlainString(),
        createdAt = expense.createdAt,
        sync = stamp.copy(deletedAt = null),
    )

private fun ExpenseWithLedger.toDomain(): Expense = Expense(
    id = UUID.fromString(expense.id),
    tripId = UUID.fromString(expense.tripId),
    amount = Money.parse(expense.amountText, expense.currency),
    categoryId = expense.categoryId?.let(UUID::fromString),
    description = expense.description,
    receiptStoragePath = expense.receiptStoragePath,
    paymentMethod = PaymentMethod.valueOf(expense.paymentMethod.uppercase(Locale.ROOT)),
    expenseDate = LocalDate.parse(expense.expenseDate).atTime(12, 0).toInstant(ZoneOffset.UTC),
    payments = payments.map {
        Payment(
            UUID.fromString(it.tripPersonId),
            it.amountPaidText.toBigDecimal(),
            SplitType.valueOf(it.paymentMode.uppercase(Locale.ROOT)),
        )
    },
    splits = splits.map {
        ExpenseSplit(
            participantId = UUID.fromString(it.tripPersonId),
            amountOwed = it.amountOwedText.toBigDecimal(),
            splitType = SplitType.valueOf(it.splitType.uppercase(Locale.ROOT)),
            shareUnits = it.shareUnitsText?.toBigDecimal(),
            percentage = it.percentageText?.toBigDecimal(),
        )
    },
    createdBy = UUID.fromString(expense.createdBy),
    createdAt = Instant.parse(expense.createdAt),
    updatedAt = Instant.parse(expense.sync.updatedAt),
    deletedAt = expense.sync.deletedAt?.let(Instant::parse),
)
