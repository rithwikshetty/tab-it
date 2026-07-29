package com.rithwikshetty.tab.sync

import com.rithwikshetty.tab.data.local.ExpenseWithLedger
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.postgresChangeFlow
import java.util.UUID
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject

public class SupabaseRemoteGateway private constructor(
    private val client: SupabaseClient,
) : RemoteGateway {
    override suspend fun signIn(email: String, password: String): AuthenticatedUser {
        require(email.isNotBlank()) { "Email is required." }
        require(password.isNotBlank()) { "Password is required." }
        client.auth.signInWith(Email) {
            this.email = email.trim().lowercase()
            this.password = password
        }
        return checkNotNull(currentUser()) { "Supabase did not establish an authenticated session." }
    }

    override suspend fun signOut() {
        client.auth.signOut()
    }

    override fun currentUser(): AuthenticatedUser? =
        client.auth.currentUserOrNull()?.let { AuthenticatedUser(it.id, it.email) }

    override suspend fun pullSnapshot(): RemoteSnapshot {
        checkNotNull(currentUser()) { "Authentication is required before synchronization." }

        val profiles = client.from("visible_profiles").select().decodeList<ProfileDto>()
        val trips = client.from("trips").select().decodeList<TripDto>()
        val people = client.from("trip_people").select().decodeList<TripPersonDto>()
        val categories = client.from("categories").select().decodeList<CategoryDto>()
        val expenses = client.from("expenses").select().decodeList<ExpenseDto>()
        val payments = client.from("expense_payments").select().decodeList<ExpensePaymentDto>()
        val splits = client.from("expense_splits").select().decodeList<ExpenseSplitDto>()
        val settlements = client.from("settlements").select().decodeList<SettlementDto>()
        val activity = client.from("activity_log").select().decodeList<ActivityDto>()
        val mutes = client.from("trip_mute_prefs").select().decodeList<TripMutePreferenceDto>()

        val paymentsByExpense = payments.map(ExpensePaymentDto::toEntity).groupBy { it.expenseId }
        val splitsByExpense = splits.map(ExpenseSplitDto::toEntity).groupBy { it.expenseId }

        return RemoteSnapshot(
            profiles = profiles.map { it.toEntity(activityLastSeenAt = null) },
            trips = trips.map(TripDto::toEntity),
            people = people.map(TripPersonDto::toEntity),
            categories = categories.map(CategoryDto::toEntity),
            expenses = expenses.map { row ->
                RemoteExpenseLedger(
                    row.toEntity(),
                    paymentsByExpense[row.id].orEmpty(),
                    splitsByExpense[row.id].orEmpty(),
                )
            },
            settlements = settlements.map(SettlementDto::toEntity),
            activity = activity.map(ActivityDto::toEntity),
            mutePreferences = mutes.map(TripMutePreferenceDto::toEntity),
        )
    }

    override suspend fun pushExpense(expense: ExpenseWithLedger): PushReceipt {
        checkNotNull(currentUser()) { "Authentication is required before synchronization." }
        val row = expense.expense
        val deletedAt = row.sync.deletedAt

        if (deletedAt == null) {
            val parameters = ExpenseRpcParameters(
                    expense = ExpensePayload(
                        id = row.id,
                        tripId = row.tripId,
                        amount = row.amountText,
                        currency = row.currency,
                        categoryId = row.categoryId,
                        description = row.description,
                        expenseDate = row.expenseDate,
                        receiptStoragePath = row.receiptStoragePath,
                        paymentMethod = row.paymentMethod,
                        lastEditedBy = row.lastEditedBy,
                        updatedAt = row.sync.updatedAt,
                        writeId = row.sync.writeId,
                    ),
                    payments = expense.payments.map {
                        PaymentPayload(
                            it.tripPersonId,
                            it.amountPaidText,
                            it.paymentMode,
                            it.sync.updatedAt,
                            it.sync.writeId,
                        )
                    },
                    splits = expense.splits.map {
                        SplitPayload(
                            it.tripPersonId,
                            it.amountOwedText,
                            it.splitType,
                            it.shareUnitsText,
                            it.percentageText,
                            it.sync.updatedAt,
                            it.sync.writeId,
                        )
                    },
                )
            client.postgrest.rpc(
                "create_expense_with_payments_and_splits",
                Json.encodeToJsonElement(parameters).jsonObject,
            )
        } else {
            client.from("expenses").update(
                ExpenseDeletePayload(deletedAt, row.sync.updatedAt, row.sync.writeId),
            ) {
                filter {
                    eq("id", row.id)
                }
            }
        }

        val accepted = client.from("expenses").select {
            filter {
                eq("id", row.id)
            }
        }.decodeSingle<ExpenseDto>()
        return PushReceipt(accepted.writeId)
    }

    override fun observeCurrentTripChanges(tripId: String): Flow<Unit> {
        UUID.fromString(tripId)
        val channel = client.channel("trip-$tripId")
        val tripChanges = channel.postgresChangeFlow<PostgresAction>(schema = "public") {
            table = "trips"
            filter("id", FilterOperator.EQ, tripId)
        }
        val peopleChanges = channel.postgresChangeFlow<PostgresAction>(schema = "public") {
            table = "trip_people"
            filter("trip_id", FilterOperator.EQ, tripId)
        }
        val expenseChanges = channel.postgresChangeFlow<PostgresAction>(schema = "public") {
            table = "expenses"
            filter("trip_id", FilterOperator.EQ, tripId)
        }
        val settlementChanges = channel.postgresChangeFlow<PostgresAction>(schema = "public") {
            table = "settlements"
            filter("trip_id", FilterOperator.EQ, tripId)
        }

        return channelFlow {
            val collectors = listOf(
                tripChanges,
                peopleChanges,
                expenseChanges,
                settlementChanges,
            ).map { changes ->
                launch(start = CoroutineStart.UNDISPATCHED) {
                    changes.collect { send(Unit) }
                }
            }
            try {
                channel.subscribe(blockUntilSubscribed = true)
                awaitCancellation()
            } finally {
                collectors.forEach { it.cancel() }
                withContext(NonCancellable) {
                    channel.unsubscribe()
                }
            }
        }
    }

    public companion object {
        public fun create(configuration: LocalBackendConfiguration): SupabaseRemoteGateway {
            val client = createSupabaseClient(
                supabaseUrl = configuration.baseUrl,
                supabaseKey = configuration.publishableKey,
            ) {
                install(Auth)
                install(Postgrest)
                install(Realtime)
            }
            return SupabaseRemoteGateway(client)
        }
    }
}
