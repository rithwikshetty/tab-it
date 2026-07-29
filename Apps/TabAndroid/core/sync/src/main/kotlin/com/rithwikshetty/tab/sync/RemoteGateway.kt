package com.rithwikshetty.tab.sync

import com.rithwikshetty.tab.data.local.ActivityEntity
import com.rithwikshetty.tab.data.local.CategoryEntity
import com.rithwikshetty.tab.data.local.ExpenseEntity
import com.rithwikshetty.tab.data.local.ExpensePaymentEntity
import com.rithwikshetty.tab.data.local.ExpenseSplitEntity
import com.rithwikshetty.tab.data.local.ExpenseWithLedger
import com.rithwikshetty.tab.data.local.ProfileEntity
import com.rithwikshetty.tab.data.local.SettlementEntity
import com.rithwikshetty.tab.data.local.TripEntity
import com.rithwikshetty.tab.data.local.TripMutePreferenceEntity
import com.rithwikshetty.tab.data.local.TripPersonEntity
import kotlinx.coroutines.flow.Flow

public data class AuthenticatedUser(
    public val id: String,
    public val email: String?,
)

public data class RemoteExpenseLedger(
    public val expense: ExpenseEntity,
    public val payments: List<ExpensePaymentEntity>,
    public val splits: List<ExpenseSplitEntity>,
)

public data class RemoteSnapshot(
    public val profiles: List<ProfileEntity>,
    public val trips: List<TripEntity>,
    public val people: List<TripPersonEntity>,
    public val categories: List<CategoryEntity>,
    public val expenses: List<RemoteExpenseLedger>,
    public val settlements: List<SettlementEntity>,
    public val activity: List<ActivityEntity>,
    public val mutePreferences: List<TripMutePreferenceEntity>,
)

public data class PushReceipt(
    public val acceptedWriteId: String,
)

public interface RemoteGateway {
    public suspend fun restoreSession(): AuthenticatedUser?

    public suspend fun signIn(email: String, password: String): AuthenticatedUser

    public suspend fun signOut()

    public suspend fun close()

    public fun currentUser(): AuthenticatedUser?

    public suspend fun pullSnapshot(): RemoteSnapshot

    public suspend fun pushExpense(expense: ExpenseWithLedger): PushReceipt

    public suspend fun pushTrip(trip: TripEntity, creator: TripPersonEntity?): PushReceipt

    public suspend fun addTripPerson(
        tripId: String,
        email: String,
        displayName: String?,
        personId: String,
    )

    public suspend fun removeTripPerson(personId: String)

    public fun observeCurrentTripChanges(tripId: String): Flow<Unit>
}
