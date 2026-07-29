package com.rithwikshetty.tab.data

import androidx.room.withTransaction
import com.rithwikshetty.tab.data.local.ExpenseEntity
import com.rithwikshetty.tab.data.local.ExpensePaymentEntity
import com.rithwikshetty.tab.data.local.ExpenseSplitEntity
import com.rithwikshetty.tab.data.local.ExpenseWithLedger
import com.rithwikshetty.tab.data.local.OutboxEntity
import com.rithwikshetty.tab.data.local.ProfileEntity
import com.rithwikshetty.tab.data.local.ReceiptDraftEntity
import com.rithwikshetty.tab.data.local.SyncStamp
import com.rithwikshetty.tab.data.local.TabDatabase
import com.rithwikshetty.tab.data.local.TripEntity
import com.rithwikshetty.tab.data.local.TripPersonEntity
import com.rithwikshetty.tab.data.local.CategoryEntity
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.ExpenseSplit
import com.rithwikshetty.tab.domain.CurrencyCatalog
import com.rithwikshetty.tab.domain.Money
import com.rithwikshetty.tab.domain.Payment
import com.rithwikshetty.tab.domain.PaymentMethod
import com.rithwikshetty.tab.domain.SplitType
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.flow.Flow
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
)

public data class LocalCategory(
    public val id: UUID,
    public val name: String,
    public val icon: String,
    public val isDefault: Boolean,
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

private fun TripEntity.toSummary(): LocalTripSummary =
    LocalTripSummary(UUID.fromString(id), name, Instant.parse(lastActivityAt))

private fun TripPersonEntity.toLocalPerson(): LocalPerson =
    LocalPerson(
        id = UUID.fromString(id),
        userId = userId?.let(UUID::fromString),
        email = email,
        displayName = displayName,
        hasJoined = joinedAt != null,
    )

private fun CategoryEntity.toLocalCategory(): LocalCategory =
    LocalCategory(UUID.fromString(id), name, icon, isDefault)

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
