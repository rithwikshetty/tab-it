package com.rithwikshetty.tab.sync

import com.rithwikshetty.tab.data.local.ActivityEntity
import com.rithwikshetty.tab.data.local.CategoryEntity
import com.rithwikshetty.tab.data.local.ExpenseEntity
import com.rithwikshetty.tab.data.local.ExpensePaymentEntity
import com.rithwikshetty.tab.data.local.ExpenseSplitEntity
import com.rithwikshetty.tab.data.local.ProfileEntity
import com.rithwikshetty.tab.data.local.SettlementEntity
import com.rithwikshetty.tab.data.local.SyncStamp
import com.rithwikshetty.tab.data.local.TripEntity
import com.rithwikshetty.tab.data.local.TripMutePreferenceEntity
import com.rithwikshetty.tab.data.local.TripPersonEntity
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

@Serializable
internal data class ProfileDto(
    val id: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("avatar_url") val avatarUrl: String?,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
    @SerialName("activity_last_seen_at") val activityLastSeenAt: String? = null,
) {
    fun toEntity(): ProfileEntity = ProfileEntity(
        id,
        displayName,
        avatarUrl,
        activityLastSeenAt,
        createdAt,
        SyncStamp(updatedAt, null, writeId, false),
    )
}

@Serializable
internal data class TripDto(
    val id: String,
    val name: String,
    val kind: String,
    @SerialName("member_signature") val memberSignature: String?,
    @SerialName("created_by") val createdBy: String,
    @SerialName("last_activity_at") val lastActivityAt: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("write_id") val writeId: String,
) {
    fun toEntity(): TripEntity = TripEntity(
        id,
        name,
        kind,
        memberSignature,
        createdBy,
        lastActivityAt,
        createdAt,
        syncStamp(updatedAt, deletedAt, writeId),
    )
}

@Serializable
internal data class CreateTripParameters(
    @SerialName("p_trip_id") val tripId: String,
    @SerialName("p_person_id") val personId: String,
    @SerialName("p_name") val name: String,
)

@Serializable
internal data class MuteUpsertPayload(
    @SerialName("trip_id") val tripId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("muted_at") val mutedAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
)

@Serializable
internal data class MarkActivitySeenParameters(
    @SerialName("p_seen_at") val seenAt: String,
)

@Serializable
internal data class TripIdParameters(
    @SerialName("p_trip_id") val tripId: String,
)

@Serializable
internal data class TripInviteDto(
    val token: String,
)

@Serializable
internal data class JoinTripInviteParameters(
    @SerialName("p_token") val token: String,
)

@Serializable
internal data class JoinedTripDto(
    @SerialName("trip_id") val tripId: String,
    @SerialName("person_id") val personId: String,
    @SerialName("trip_name") val tripName: String,
)

@Serializable
internal data class TripUpdatePayload(
    val name: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
)

@Serializable
internal data class AddTripPersonParameters(
    @SerialName("p_trip_id") val tripId: String,
    @SerialName("p_email") val email: String,
    @SerialName("p_display_name") val displayName: String?,
    @SerialName("p_person_id") val personId: String,
)

@Serializable
internal data class RemoveTripPersonParameters(
    @SerialName("p_person_id") val personId: String,
)

@Serializable
internal data class NonGroupParticipantPayload(
    val email: String,
    @SerialName("display_name") val displayName: String,
)

@Serializable
internal data class ResolveNonGroupParameters(
    @SerialName("p_participants") val participants: List<NonGroupParticipantPayload>,
)

@Serializable
internal data class TripPersonDto(
    val id: String,
    @SerialName("trip_id") val tripId: String,
    @SerialName("user_id") val userId: String?,
    val email: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("invited_by") val invitedBy: String?,
    @SerialName("joined_at") val joinedAt: String?,
    @SerialName("removed_at") val removedAt: String?,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
) {
    fun toEntity(): TripPersonEntity = TripPersonEntity(
        id,
        tripId,
        userId,
        email,
        displayName,
        invitedBy,
        joinedAt,
        removedAt,
        createdAt,
        syncStamp(updatedAt, null, writeId),
    )
}

@Serializable
internal data class CategoryDto(
    val id: String,
    @SerialName("trip_id") val tripId: String?,
    val name: String,
    val icon: String,
    @SerialName("is_default") val isDefault: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("write_id") val writeId: String,
) {
    fun toEntity(): CategoryEntity = CategoryEntity(
        id,
        tripId,
        name,
        icon,
        isDefault,
        createdAt,
        syncStamp(updatedAt, deletedAt, writeId),
    )
}

@Serializable
internal data class ExpenseDto(
    val id: String,
    @SerialName("trip_id") val tripId: String,
    val amount: JsonElement,
    val currency: String,
    @SerialName("category_id") val categoryId: String?,
    val description: String,
    @SerialName("expense_date") val expenseDate: String,
    @SerialName("receipt_storage_path") val receiptStoragePath: String?,
    @SerialName("payment_method") val paymentMethod: String,
    @SerialName("created_by") val createdBy: String,
    @SerialName("last_edited_by") val lastEditedBy: String?,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("write_id") val writeId: String,
) {
    fun toEntity(): ExpenseEntity = ExpenseEntity(
        id,
        tripId,
        amount.numericText(),
        currency,
        categoryId,
        description,
        expenseDate,
        receiptStoragePath,
        paymentMethod,
        createdBy,
        lastEditedBy,
        createdAt,
        syncStamp(updatedAt, deletedAt, writeId),
    )
}

@Serializable
internal data class ExpensePaymentDto(
    @SerialName("expense_id") val expenseId: String,
    @SerialName("trip_person_id") val tripPersonId: String,
    @SerialName("amount_paid") val amountPaid: JsonElement,
    @SerialName("payment_mode") val paymentMode: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
) {
    fun toEntity(): ExpensePaymentEntity = ExpensePaymentEntity(
        expenseId,
        tripPersonId,
        amountPaid.numericText(),
        paymentMode,
        createdAt,
        syncStamp(updatedAt, null, writeId),
    )
}

@Serializable
internal data class ExpenseSplitDto(
    @SerialName("expense_id") val expenseId: String,
    @SerialName("trip_person_id") val tripPersonId: String,
    @SerialName("amount_owed") val amountOwed: JsonElement,
    @SerialName("split_type") val splitType: String,
    @SerialName("share_units") val shareUnits: JsonElement?,
    val percentage: JsonElement?,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
) {
    fun toEntity(): ExpenseSplitEntity = ExpenseSplitEntity(
        expenseId,
        tripPersonId,
        amountOwed.numericText(),
        splitType,
        shareUnits?.nullableNumericText(),
        percentage?.nullableNumericText(),
        createdAt,
        syncStamp(updatedAt, null, writeId),
    )
}

@Serializable
internal data class SettlementDto(
    val id: String,
    @SerialName("trip_id") val tripId: String,
    @SerialName("from_person_id") val fromPersonId: String,
    @SerialName("to_person_id") val toPersonId: String,
    val amount: JsonElement,
    val currency: String,
    val note: String?,
    @SerialName("settled_at") val settledAt: String,
    @SerialName("created_by") val createdBy: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String?,
    @SerialName("write_id") val writeId: String,
) {
    fun toEntity(): SettlementEntity = SettlementEntity(
        id,
        tripId,
        fromPersonId,
        toPersonId,
        amount.numericText(),
        currency,
        note,
        settledAt,
        createdBy,
        createdAt,
        syncStamp(updatedAt, deletedAt, writeId),
    )
}

@Serializable
internal data class SettlementUpsertPayload(
    val id: String,
    @SerialName("trip_id") val tripId: String,
    @SerialName("from_person_id") val fromPersonId: String,
    @SerialName("to_person_id") val toPersonId: String,
    val amount: String,
    val currency: String,
    val note: String?,
    @SerialName("settled_at") val settledAt: String,
    @SerialName("created_by") val createdBy: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
)

@Serializable
internal data class SettlementDeletePayload(
    @SerialName("deleted_at") val deletedAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
)

@Serializable
internal data class ActivityDto(
    val id: String,
    @SerialName("trip_id") val tripId: String,
    @SerialName("actor_id") val actorId: String,
    val action: String,
    @SerialName("entity_type") val entityType: String,
    @SerialName("entity_id") val entityId: String,
    val timestamp: String,
    @SerialName("snapshot_json") val snapshotJson: JsonElement?,
) {
    fun toEntity(): ActivityEntity = ActivityEntity(
        id,
        tripId,
        actorId,
        action,
        entityType,
        entityId,
        timestamp,
        snapshotJson?.takeUnless { it is JsonNull }?.toString(),
    )
}

@Serializable
internal data class TripMutePreferenceDto(
    @SerialName("trip_id") val tripId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("muted_at") val mutedAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
) {
    fun toEntity(): TripMutePreferenceEntity = TripMutePreferenceEntity(
        tripId,
        userId,
        mutedAt,
        syncStamp(updatedAt, null, writeId),
    )
}

@Serializable
internal data class ExpensePayload(
    val id: String,
    @SerialName("trip_id") val tripId: String,
    val amount: String,
    val currency: String,
    @SerialName("category_id") val categoryId: String?,
    val description: String,
    @SerialName("expense_date") val expenseDate: String,
    @SerialName("receipt_storage_path") val receiptStoragePath: String?,
    @SerialName("payment_method") val paymentMethod: String,
    @SerialName("last_edited_by") val lastEditedBy: String?,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
)

@Serializable
internal data class PaymentPayload(
    @SerialName("trip_person_id") val tripPersonId: String,
    @SerialName("amount_paid") val amountPaid: String,
    @SerialName("payment_mode") val paymentMode: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
)

@Serializable
internal data class SplitPayload(
    @SerialName("trip_person_id") val tripPersonId: String,
    @SerialName("amount_owed") val amountOwed: String,
    @SerialName("split_type") val splitType: String,
    @SerialName("share_units") val shareUnits: String?,
    val percentage: String?,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
)

@Serializable
internal data class ExpenseRpcParameters(
    @SerialName("p_expense") val expense: ExpensePayload,
    @SerialName("p_payments") val payments: List<PaymentPayload>,
    @SerialName("p_splits") val splits: List<SplitPayload>,
)

@Serializable
internal data class ExpenseDeletePayload(
    @SerialName("deleted_at") val deletedAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("write_id") val writeId: String,
)

private fun syncStamp(updatedAt: String, deletedAt: String?, writeId: String): SyncStamp =
    SyncStamp(updatedAt, deletedAt, writeId, false)

private fun JsonElement.numericText(): String =
    (this as? JsonPrimitive)?.content
        ?: error("Expected a numeric JSON primitive.")

private fun JsonElement.nullableNumericText(): String? =
    if (this is JsonNull) null else numericText()
