package com.rithwikshetty.tab.ui.app

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.rithwikshetty.tab.TabContainer
import com.rithwikshetty.tab.data.LocalTripSummary
import com.rithwikshetty.tab.data.LocalCategory
import com.rithwikshetty.tab.data.LocalPerson
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.domain.BalanceEngine
import com.rithwikshetty.tab.domain.DebtSimplifier
import com.rithwikshetty.tab.domain.Settlement
import com.rithwikshetty.tab.domain.SimplifiedDebt
import com.rithwikshetty.tab.domain.UserBalance
import com.rithwikshetty.tab.domain.Money
import com.rithwikshetty.tab.domain.SplitwiseImport
import com.rithwikshetty.tab.domain.SplitwiseImportResult
import com.rithwikshetty.tab.TripCsvExporter
import com.rithwikshetty.tab.ui.friends.FriendsPresenter
import com.rithwikshetty.tab.ui.friends.FriendsUiState
import com.rithwikshetty.tab.ui.activity.ActivityPresenter
import com.rithwikshetty.tab.ui.activity.ActivityUiState
import java.math.BigDecimal
import java.time.Instant
import com.rithwikshetty.tab.sync.AuthenticatedUser
import com.rithwikshetty.tab.sync.RealtimeSyncCoordinator
import com.rithwikshetty.tab.sync.RemoteParticipant
import java.util.UUID
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed interface SessionState {
    data object Loading : SessionState
    data object BackendUnavailable : SessionState
    data object SignedOut : SessionState
    data class SignedIn(val user: AuthenticatedUser) : SessionState
}

data class TabUiState(
    val session: SessionState = SessionState.Loading,
    val trips: List<LocalTripSummary> = emptyList(),
    val tripContent: TripContentUiState = TripContentUiState(),
    val friends: FriendsUiState = FriendsUiState(),
    val activity: ActivityUiState = ActivityUiState(),
    val importPreview: ImportPreviewUiState? = null,
    val isWorking: Boolean = false,
    val message: String? = null,
)

data class ImportPreviewUiState(
    val result: SplitwiseImportResult,
    val sourceName: String,
)

data class TripContentUiState(
    val tripId: UUID? = null,
    val people: List<LocalPerson> = emptyList(),
    val categories: List<LocalCategory> = emptyList(),
    val expenses: List<Expense> = emptyList(),
    val settlements: List<Settlement> = emptyList(),
    val balances: List<UserBalance> = emptyList(),
    val simplifiedDebts: List<SimplifiedDebt> = emptyList(),
)

@OptIn(ExperimentalCoroutinesApi::class)
class TabViewModel(
    private val container: TabContainer,
) : ViewModel() {
    private val session = MutableStateFlow<SessionState>(SessionState.Loading)
    private val isWorking = MutableStateFlow(false)
    private val message = MutableStateFlow<String?>(null)
    private val visibleTripId = MutableStateFlow<UUID?>(null)
    private val importPreview = MutableStateFlow<ImportPreviewUiState?>(null)
    private var realtimeJob: Job? = null

    private val tripContent = combine(
        visibleTripId,
        visibleTripId.flatMapLatest { id ->
            id?.let(container.tripRepository::observePeople) ?: flowOf(emptyList())
        },
        visibleTripId.flatMapLatest { id ->
            id?.let(container.tripRepository::observeCategories) ?: flowOf(emptyList())
        },
        visibleTripId.flatMapLatest { id ->
            id?.let(container.expenseRepository::observeExpenses) ?: flowOf(emptyList())
        },
        visibleTripId.flatMapLatest { id ->
            id?.let(container.settlementRepository::observeSettlements) ?: flowOf(emptyList())
        },
    ) { tripId, people, categories, expenses, settlements ->
        val balances = BalanceEngine.compute(expenses, settlements)
        TripContentUiState(
            tripId = tripId,
            people = people,
            categories = categories,
            expenses = expenses,
            settlements = settlements,
            balances = balances,
            simplifiedDebts = DebtSimplifier.simplify(balances),
        )
    }

    private val friends = combine(
        session,
        container.balanceRepository.snapshot,
    ) { currentSession, snapshot ->
        val user = currentSession as? SessionState.SignedIn
        if (user == null) {
            FriendsUiState()
        } else {
            FriendsPresenter.present(snapshot, UUID.fromString(user.user.id))
        }
    }

    private val activity = session.flatMapLatest { currentSession ->
        val user = currentSession as? SessionState.SignedIn
        if (user == null) {
            flowOf(ActivityUiState())
        } else {
            val id = UUID.fromString(user.user.id)
            container.activityRepository.observe(id).map {
                ActivityPresenter.present(it, id)
            }
        }
    }

    private val ledgerContent = combine(tripContent, friends, activity, ::Triple)
    private val screenContent = combine(ledgerContent, importPreview, ::Pair)

    val uiState: StateFlow<TabUiState> = combine(
        session,
        container.tripRepository.observeTrips(),
        screenContent,
        isWorking,
        message,
    ) { currentSession, trips, content, working, currentMessage ->
        TabUiState(
            session = currentSession,
            trips = trips,
            tripContent = content.first.first,
            friends = content.first.second,
            activity = content.first.third,
            importPreview = content.second,
            isWorking = working,
            message = currentMessage,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = TabUiState(),
    )

    init {
        restoreSession()
    }

    fun signIn(email: String, password: String) {
        val remote = container.remoteGateway ?: run {
            session.value = SessionState.BackendUnavailable
            return
        }
        if (email.isBlank() || password.isBlank()) {
            message.value = "Enter your email and password."
            return
        }
        launchWorking {
            val user = remote.signIn(email, password)
            session.value = SessionState.SignedIn(user)
            sync()
        }
    }

    fun refresh() {
        launchWorking { sync() }
    }

    fun createTrip(name: String, onCreated: (UUID) -> Unit = {}) {
        val user = signedInUser() ?: return
        val email = user.email ?: run {
            message.value = "A verified email is required to create a trip."
            return
        }
        launchWorking {
            val id = container.tripRepository.create(
                name = name,
                userId = UUID.fromString(user.id),
                email = email,
                displayName = email.substringBefore("@"),
            )
            onCreated(id)
            sync()
        }
    }

    fun renameTrip(id: UUID, name: String) {
        launchWorking {
            container.tripRepository.rename(id, name)
            sync()
        }
    }

    fun archiveTrip(id: UUID, onArchived: () -> Unit = {}) {
        launchWorking {
            container.tripRepository.archive(id)
            onArchived()
            sync()
        }
    }

    fun signOut() {
        val remote = container.remoteGateway ?: return
        launchWorking {
            val report = checkNotNull(container.syncEngine).syncOnce()
            check(report.pushFailures == 0 && report.pullCompleted) {
                "Sign out needs a successful sync so local changes are not lost."
            }
            remote.signOut()
            container.tripRepository.clearAccountData()
            session.value = SessionState.SignedOut
        }
    }

    fun setVisibleTrip(id: UUID?) {
        realtimeJob?.cancel()
        realtimeJob = null
        visibleTripId.value = id
        if (id == null || session.value !is SessionState.SignedIn) return
        val remote = container.remoteGateway ?: return
        val engine = container.syncEngine ?: return
        realtimeJob = RealtimeSyncCoordinator(remote, engine)
            .start(viewModelScope, id.toString())
    }

    fun saveExpense(expense: Expense, receiptUri: String?) {
        launchWorking {
            val prepared = receiptUri?.let {
                container.receiptStore.prepare(
                    Uri.parse(it),
                    expense.tripId,
                    expense.id,
                )
            }
            val storedExpense = prepared?.let {
                expense.copy(receiptStoragePath = it.remotePath)
            } ?: expense
            container.expenseRepository.save(storedExpense, receiptLocalUri = prepared?.localUri)
            sync()
        }
    }

    fun loadReceipt(expenseId: UUID, remotePath: String, onLoaded: (ByteArray) -> Unit) {
        viewModelScope.launch {
            runCatching {
                val local = container.expenseRepository
                    .findReceiptLocalUri(expenseId)
                    ?.let { container.receiptStore.readLocal(it) }
                local ?: checkNotNull(container.remoteGateway).downloadReceipt(remotePath)
            }.onSuccess(onLoaded)
                .onFailure { message.value = "Couldn't load receipt." }
        }
    }

    fun exportTrip(tripId: UUID, onReady: (String) -> Unit) {
        launchWorking {
            val trip = checkNotNull(container.tripRepository.observeTrip(tripId).first()) {
                "Trip not found."
            }
            val people = container.tripRepository.observePeople(tripId).first()
            val categories = container.tripRepository.observeCategories(tripId).first()
            val expenses = container.expenseRepository.observeExpenses(tripId).first()
            val settlements = container.settlementRepository.observeSettlements(tripId).first()
            val csv = TripCsvExporter.generate(expenses, settlements, people, categories)
            val uri = container.dataTransferStore.writeCsv(trip.name, csv)
            onReady(uri.toString())
        }
    }

    fun previewSplitwiseImport(uri: String) {
        launchWorking {
            val parsed = SplitwiseImport.parse(
                container.dataTransferStore.readCsv(Uri.parse(uri)),
            )
            importPreview.value = ImportPreviewUiState(
                result = parsed,
                sourceName = Uri.parse(uri).lastPathSegment ?: "Splitwise CSV",
            )
        }
    }

    fun clearImportPreview() {
        importPreview.value = null
    }

    fun applySplitwiseImport(
        tripName: String,
        selfPerson: String,
        onImported: (UUID) -> Unit,
    ) {
        val user = signedInUser() ?: return
        val preview = importPreview.value ?: return
        val cleanName = tripName.trim()
        if (cleanName.isEmpty() || selfPerson !in preview.result.people) {
            message.value = "Choose a trip name and which person is you."
            return
        }
        if (user.email == null) {
            message.value = "A verified email is required to import a trip."
            return
        }
        launchWorking {
            val tripId = container.splitwiseImporter.run(
                preview.result,
                cleanName,
                selfPerson,
                user,
            )
            importPreview.value = null
            onImported(tripId)
        }
    }

    fun deleteExpense(id: UUID) {
        launchWorking {
            container.expenseRepository.softDelete(id, java.time.Instant.now())
            sync()
        }
    }

    fun addTripPerson(tripId: UUID, email: String, displayName: String?) {
        val remote = container.remoteGateway ?: return
        launchWorking {
            sync()
            remote.addTripPerson(
                tripId = tripId.toString(),
                email = email,
                displayName = displayName,
                personId = UUID.randomUUID().toString(),
            )
            sync()
        }
    }

    fun removeTripPerson(personId: UUID) {
        val remote = container.remoteGateway ?: return
        launchWorking {
            remote.removeTripPerson(personId.toString())
            sync()
        }
    }

    fun resolveNonGroupContainer(
        participants: List<RemoteParticipant>,
        onResolved: (UUID) -> Unit,
    ) {
        val remote = container.remoteGateway ?: return
        launchWorking {
            val id = UUID.fromString(remote.resolveNonGroupContainer(participants))
            sync()
            onResolved(id)
        }
    }

    fun saveSettlement(
        tripId: UUID,
        fromPersonId: UUID,
        toPersonId: UUID,
        amountText: String,
        currency: String,
        note: String?,
        existing: Settlement? = null,
    ) {
        val user = signedInUser() ?: return
        launchWorking {
            val now = Instant.now()
            val amount = runCatching { Money.parse(amountText.trim(), currency) }
                .getOrElse { throw IllegalArgumentException("Enter a valid amount.") }
            require(amount.amount > BigDecimal.ZERO) { "Amount must be greater than zero." }
            val settlement = Settlement(
                id = existing?.id ?: UUID.randomUUID(),
                tripId = tripId,
                fromUserId = fromPersonId,
                toUserId = toPersonId,
                amount = amount,
                note = note?.trim()?.ifEmpty { null },
                settledAt = existing?.settledAt ?: now,
                createdBy = existing?.createdBy ?: UUID.fromString(user.id),
                createdAt = existing?.createdAt ?: now,
                updatedAt = now,
                deletedAt = null,
            )
            container.settlementRepository.save(settlement)
            sync()
        }
    }

    fun deleteSettlement(id: UUID) {
        launchWorking {
            container.settlementRepository.softDelete(id)
            sync()
        }
    }

    fun markActivitySeen() {
        val user = signedInUser() ?: return
        val remote = container.remoteGateway ?: return
        viewModelScope.launch {
            val now = Instant.now()
            runCatching {
                container.activityRepository.markSeen(UUID.fromString(user.id), now)
                val accepted = remote.markActivitySeen(now.toString())
                container.activityRepository.markSeen(
                    UUID.fromString(user.id),
                    Instant.parse(accepted),
                )
            }.onFailure { message.value = it.userMessage() }
        }
    }

    fun setTripMuted(tripId: UUID, muted: Boolean) {
        val user = signedInUser() ?: return
        launchWorking {
            container.activityRepository.setTripMuted(
                tripId,
                UUID.fromString(user.id),
                muted,
            )
            sync()
        }
    }

    fun shareTripInvite(tripId: UUID, onReady: (String) -> Unit) {
        val remote = container.remoteGateway ?: return
        launchWorking {
            val token = remote.getOrCreateTripInvite(tripId.toString())
            onReady("https://tab-it.app/join/$token")
        }
    }

    fun revokeTripInvite(tripId: UUID) {
        val remote = container.remoteGateway ?: return
        launchWorking {
            remote.revokeTripInvite(tripId.toString())
            message.value = "Invite link revoked."
        }
    }

    fun joinTripInvite(linkOrToken: String, onJoined: (UUID) -> Unit) {
        val remote = container.remoteGateway ?: return
        val token = inviteToken(linkOrToken) ?: run {
            message.value = "Enter a valid Tab invite link or token."
            return
        }
        launchWorking {
            val joined = remote.joinTripWithInvite(token)
            sync()
            onJoined(UUID.fromString(joined.tripId))
        }
    }

    fun clearMessage() {
        message.value = null
    }

    private fun restoreSession() {
        viewModelScope.launch {
            val remote = container.remoteGateway
            if (remote == null) {
                session.value = SessionState.BackendUnavailable
                return@launch
            }
            runCatching { remote.restoreSession() }
                .onSuccess { user ->
                    session.value = user?.let(SessionState::SignedIn) ?: SessionState.SignedOut
                    if (user != null) {
                        launchWorking { sync() }
                    }
                }
                .onFailure {
                    session.value = SessionState.SignedOut
                    message.value = it.userMessage()
                }
        }
    }

    private suspend fun sync() {
        val report = checkNotNull(container.syncEngine).syncOnce()
        if (!report.pullCompleted || report.pushFailures > 0) {
            error(report.errorMessage ?: "Some changes are waiting for the local backend.")
        }
        message.value = if (report.pushed > 0) {
            "Saved locally and synced."
        } else {
            null
        }
    }

    private fun signedInUser(): AuthenticatedUser? =
        (session.value as? SessionState.SignedIn)?.user.also {
            if (it == null) message.value = "Sign in before changing a trip."
        }

    private fun inviteToken(value: String): String? {
        val trimmed = value.trim().lowercase()
        val token = trimmed.substringAfterLast('/')
        return token.takeIf { it.matches(Regex("[0-9a-f]{32}")) }
    }

    private fun launchWorking(block: suspend () -> Unit) {
        if (isWorking.value) return
        viewModelScope.launch {
            isWorking.value = true
            message.value = null
            runCatching { block() }
                .onFailure { message.value = it.userMessage() }
            isWorking.value = false
        }
    }

    class Factory(
        private val container: TabContainer,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            require(modelClass.isAssignableFrom(TabViewModel::class.java))
            return TabViewModel(container) as T
        }
    }
}

private fun Throwable.userMessage(): String =
    (message ?: "Something went wrong. Try again.")
        .replace(
            Regex("(?i)(apikey|authorization|token|secret)\\s*[:=]\\s*\\S+"),
            "$1=<redacted>",
        )
        .take(200)
