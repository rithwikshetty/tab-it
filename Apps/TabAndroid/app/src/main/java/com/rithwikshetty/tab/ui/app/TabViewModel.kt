package com.rithwikshetty.tab.ui.app

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.rithwikshetty.tab.TabContainer
import com.rithwikshetty.tab.data.LocalTripSummary
import com.rithwikshetty.tab.data.LocalCategory
import com.rithwikshetty.tab.data.LocalPerson
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.sync.AuthenticatedUser
import com.rithwikshetty.tab.sync.RealtimeSyncCoordinator
import java.util.UUID
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
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
    val isWorking: Boolean = false,
    val message: String? = null,
)

data class TripContentUiState(
    val tripId: UUID? = null,
    val people: List<LocalPerson> = emptyList(),
    val categories: List<LocalCategory> = emptyList(),
    val expenses: List<Expense> = emptyList(),
)

@OptIn(ExperimentalCoroutinesApi::class)
class TabViewModel(
    private val container: TabContainer,
) : ViewModel() {
    private val session = MutableStateFlow<SessionState>(SessionState.Loading)
    private val isWorking = MutableStateFlow(false)
    private val message = MutableStateFlow<String?>(null)
    private val visibleTripId = MutableStateFlow<UUID?>(null)
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
    ) { tripId, people, categories, expenses ->
        TripContentUiState(tripId, people, categories, expenses)
    }

    val uiState: StateFlow<TabUiState> = combine(
        session,
        container.tripRepository.observeTrips(),
        tripContent,
        isWorking,
        message,
    ) { currentSession, trips, currentTripContent, working, currentMessage ->
        TabUiState(currentSession, trips, currentTripContent, working, currentMessage)
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

    fun saveExpense(expense: Expense) {
        launchWorking {
            container.expenseRepository.save(expense)
            sync()
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
