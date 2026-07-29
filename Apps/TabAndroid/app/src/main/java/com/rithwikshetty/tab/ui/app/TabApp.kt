package com.rithwikshetty.tab.ui.app

import android.content.Intent
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Luggage
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.rithwikshetty.tab.ui.auth.AuthScreen
import com.rithwikshetty.tab.ui.auth.BackendUnavailableScreen
import com.rithwikshetty.tab.ui.activity.ActivityScreen
import com.rithwikshetty.tab.ui.expenses.ExpenseDetailScreen
import com.rithwikshetty.tab.ui.expenses.ExpenseEditorScreen
import com.rithwikshetty.tab.ui.friends.FriendsScreen
import com.rithwikshetty.tab.ui.friends.FriendDetailScreen
import com.rithwikshetty.tab.ui.friends.NonGroupExpensePickerScreen
import com.rithwikshetty.tab.ui.settlements.SettlementDetailScreen
import com.rithwikshetty.tab.ui.settlements.SettlementEditorScreen
import com.rithwikshetty.tab.ui.trips.TripDetailScreen
import com.rithwikshetty.tab.ui.trips.TripsScreen
import com.rithwikshetty.tab.domain.SimplifiedDebt
import java.math.BigDecimal
import java.util.UUID
import kotlinx.serialization.Serializable

@Composable
fun TabApp(
    viewModel: TabViewModel,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val message = state.message
    LaunchedEffect(message) {
        if (message != null) {
            snackbar.showSnackbar(message)
            viewModel.clearMessage()
        }
    }

    when (state.session) {
        SessionState.Loading -> LoadingScreen(modifier)
        SessionState.BackendUnavailable -> BackendUnavailableScreen(modifier)
        SessionState.SignedOut -> AuthScreen(
            isWorking = state.isWorking,
            onSignIn = viewModel::signIn,
            modifier = modifier,
        )
        is SessionState.SignedIn -> SignedInApp(
            state = state,
            snackbar = snackbar,
            onRefresh = viewModel::refresh,
            onCreateTrip = viewModel::createTrip,
            onRenameTrip = viewModel::renameTrip,
            onArchiveTrip = viewModel::archiveTrip,
            onTripVisible = viewModel::setVisibleTrip,
            onSaveExpense = viewModel::saveExpense,
            onDeleteExpense = viewModel::deleteExpense,
            onSaveSettlement = viewModel::saveSettlement,
            onDeleteSettlement = viewModel::deleteSettlement,
            onAddTripPerson = viewModel::addTripPerson,
            onRemoveTripPerson = viewModel::removeTripPerson,
            onResolveNonGroup = viewModel::resolveNonGroupContainer,
            onMarkActivitySeen = viewModel::markActivitySeen,
            onSetTripMuted = viewModel::setTripMuted,
            onShareTripInvite = viewModel::shareTripInvite,
            onRevokeTripInvite = viewModel::revokeTripInvite,
            onJoinTripInvite = viewModel::joinTripInvite,
            onSignOut = viewModel::signOut,
            modifier = modifier,
        )
    }
}

@Composable
private fun SignedInApp(
    state: TabUiState,
    snackbar: SnackbarHostState,
    onRefresh: () -> Unit,
    onCreateTrip: (String, (UUID) -> Unit) -> Unit,
    onRenameTrip: (UUID, String) -> Unit,
    onArchiveTrip: (UUID, () -> Unit) -> Unit,
    onTripVisible: (UUID?) -> Unit,
    onSaveExpense: (com.rithwikshetty.tab.domain.Expense) -> Unit,
    onDeleteExpense: (UUID) -> Unit,
    onSaveSettlement: (
        UUID,
        UUID,
        UUID,
        String,
        String,
        String?,
        com.rithwikshetty.tab.domain.Settlement?,
    ) -> Unit,
    onDeleteSettlement: (UUID) -> Unit,
    onAddTripPerson: (UUID, String, String?) -> Unit,
    onRemoveTripPerson: (UUID) -> Unit,
    onResolveNonGroup: (
        List<com.rithwikshetty.tab.sync.RemoteParticipant>,
        (UUID) -> Unit,
    ) -> Unit,
    onMarkActivitySeen: () -> Unit,
    onSetTripMuted: (UUID, Boolean) -> Unit,
    onShareTripInvite: (UUID, (String) -> Unit) -> Unit,
    onRevokeTripInvite: (UUID) -> Unit,
    onJoinTripInvite: (String, (UUID) -> Unit) -> Unit,
    onSignOut: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val navController = rememberNavController()
    val context = LocalContext.current
    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val showNavigation = topDestinations.any {
        currentRoute == it.route::class.qualifiedName
    } || currentRoute == TripRoute::class.qualifiedName

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val useNavigationRail = maxWidth >= 600.dp
        Row(modifier = Modifier.fillMaxSize()) {
            if (useNavigationRail && showNavigation) {
                AppNavigationRail(
                    currentRoute = currentRoute,
                    onOpen = navController::openTopLevel,
                )
            }
            Scaffold(
                modifier = Modifier.weight(1f),
                snackbarHost = { SnackbarHost(snackbar) },
                bottomBar = {
                    if (!useNavigationRail && showNavigation) {
                        AppNavigationBar(
                            currentRoute = currentRoute,
                            onOpen = navController::openTopLevel,
                        )
                    }
                },
            ) { contentPadding ->
                NavHost(
                    navController = navController,
                    startDestination = TripsRoute,
                    modifier = Modifier.padding(contentPadding),
                ) {
            composable<FriendsRoute> {
                LaunchedEffect(Unit) { onTripVisible(null) }
                FriendsScreen(
                    state = state.friends,
                    isWorking = state.isWorking,
                    onRefresh = onRefresh,
                    onAddExpense = {
                        navController.navigate(NonGroupExpensePickerRoute)
                    },
                    onOpenFriend = {
                        navController.navigate(FriendRoute(it))
                    },
                )
            }
            composable<TripsRoute> {
                LaunchedEffect(Unit) { onTripVisible(null) }
                TripsScreen(
                    trips = state.trips,
                    isWorking = state.isWorking,
                    onRefresh = onRefresh,
                    onCreate = { name ->
                        onCreateTrip(name) { id ->
                            navController.navigate(TripRoute(id.toString()))
                        }
                    },
                    onOpenTrip = { navController.navigate(TripRoute(it.toString())) },
                )
            }
            composable<ActivityRoute> {
                LaunchedEffect(Unit) { onTripVisible(null) }
                DisposableEffect(Unit) {
                    onDispose(onMarkActivitySeen)
                }
                ActivityScreen(
                    state = state.activity,
                    trips = state.trips,
                    isWorking = state.isWorking,
                    onRefresh = onRefresh,
                    onOpenTrip = {
                        navController.navigate(TripRoute(it.toString()))
                    },
                )
            }
            composable<SettingsRoute> {
                LaunchedEffect(Unit) { onTripVisible(null) }
                SettingsScreen(
                    email = (state.session as SessionState.SignedIn).user.email,
                    isWorking = state.isWorking,
                    onJoinTrip = { value ->
                        onJoinTripInvite(value) { tripId ->
                            navController.navigate(TripRoute(tripId.toString()))
                        }
                    },
                    onSignOut = onSignOut,
                )
            }
            composable<TripRoute> { entry ->
                val route = entry.toRoute<TripRoute>()
                val id = UUID.fromString(route.id)
                LaunchedEffect(id) {
                    onTripVisible(id)
                }
                val tripContent = state.tripContent
                    .takeIf { it.tripId == id }
                    ?: TripContentUiState(tripId = id)
                TripDetailScreen(
                    trip = state.trips.firstOrNull { it.id == id },
                    content = tripContent,
                    currentUserId = UUID.fromString(
                        (state.session as SessionState.SignedIn).user.id,
                    ),
                    isMuted = id in state.activity.mutedTripIds,
                    onBack = navController::popBackStack,
                    onRename = { onRenameTrip(id, it) },
                    onArchive = {
                        onArchiveTrip(id) {
                            navController.popBackStack()
                        }
                    },
                    onToggleMute = { muted -> onSetTripMuted(id, muted) },
                    onShareInvite = {
                        onShareTripInvite(id) { url ->
                            context.startActivity(
                                Intent.createChooser(
                                    Intent(Intent.ACTION_SEND).apply {
                                        type = "text/plain"
                                        putExtra(Intent.EXTRA_TEXT, url)
                                    },
                                    "Share trip invite",
                                ),
                            )
                        }
                    },
                    onRevokeInvite = { onRevokeTripInvite(id) },
                    onAddExpense = {
                        navController.navigate(NewExpenseRoute(id.toString()))
                    },
                    onOpenExpense = { expenseId ->
                        navController.navigate(
                            ExpenseRoute(id.toString(), expenseId.toString()),
                        )
                    },
                    onAddPerson = { email, displayName ->
                        onAddTripPerson(id, email, displayName)
                    },
                    onRemovePerson = onRemoveTripPerson,
                    onSettle = { debt ->
                        navController.navigate(
                            SettleRoute(
                                tripId = id.toString(),
                                fromId = debt?.fromUser?.toString(),
                                toId = debt?.toUser?.toString(),
                                currency = debt?.currency,
                                amount = debt?.amount?.toPlainString(),
                            ),
                        )
                    },
                    onOpenSettlement = { settlementId ->
                        navController.navigate(
                            SettlementRoute(id.toString(), settlementId.toString()),
                        )
                    },
                )
            }
            composable<NewExpenseRoute> { entry ->
                val route = entry.toRoute<NewExpenseRoute>()
                val tripId = UUID.fromString(route.tripId)
                LaunchedEffect(tripId) {
                    onTripVisible(tripId)
                }
                val tripContent = state.tripContent
                    .takeIf { it.tripId == tripId }
                    ?: TripContentUiState(tripId = tripId)
                ExpenseEditorScreen(
                    tripId = tripId,
                    currentUserId = UUID.fromString(
                        (state.session as SessionState.SignedIn).user.id,
                    ),
                    people = tripContent.people,
                    categories = tripContent.categories,
                    existing = null,
                    isWorking = state.isWorking,
                    onBack = navController::popBackStack,
                    onSave = onSaveExpense,
                )
            }
            composable<ExpenseRoute> { entry ->
                val route = entry.toRoute<ExpenseRoute>()
                val tripId = UUID.fromString(route.tripId)
                val expenseId = UUID.fromString(route.expenseId)
                LaunchedEffect(tripId) {
                    onTripVisible(tripId)
                }
                val tripContent = state.tripContent
                    .takeIf { it.tripId == tripId }
                    ?: TripContentUiState(tripId = tripId)
                val expense = tripContent.expenses.firstOrNull { it.id == expenseId }
                ExpenseDetailScreen(
                    expense = expense,
                    people = tripContent.people,
                    category = tripContent.categories
                        .firstOrNull { it.id == expense?.categoryId },
                    onBack = navController::popBackStack,
                    onEdit = {
                        navController.navigate(
                            EditExpenseRoute(route.tripId, route.expenseId),
                        )
                    },
                    onDelete = {
                        onDeleteExpense(expenseId)
                        navController.popBackStack()
                    },
                )
            }
            composable<EditExpenseRoute> { entry ->
                val route = entry.toRoute<EditExpenseRoute>()
                val tripId = UUID.fromString(route.tripId)
                val expenseId = UUID.fromString(route.expenseId)
                LaunchedEffect(tripId) {
                    onTripVisible(tripId)
                }
                val tripContent = state.tripContent
                    .takeIf { it.tripId == tripId }
                    ?: TripContentUiState(tripId = tripId)
                ExpenseEditorScreen(
                    tripId = tripId,
                    currentUserId = UUID.fromString(
                        (state.session as SessionState.SignedIn).user.id,
                    ),
                    people = tripContent.people,
                    categories = tripContent.categories,
                    existing = tripContent.expenses.firstOrNull { it.id == expenseId },
                    isWorking = state.isWorking,
                    onBack = navController::popBackStack,
                    onSave = onSaveExpense,
                )
            }
            composable<SettleRoute> { entry ->
                val route = entry.toRoute<SettleRoute>()
                val tripId = UUID.fromString(route.tripId)
                LaunchedEffect(tripId) { onTripVisible(tripId) }
                val tripContent = state.tripContent
                    .takeIf { it.tripId == tripId }
                    ?: TripContentUiState(tripId = tripId)
                SettlementEditorScreen(
                    people = tripContent.people,
                    existing = null,
                    suggestion = route.toSuggestion(),
                    isWorking = state.isWorking,
                    onBack = navController::popBackStack,
                    onSave = { fromId, toId, amount, currency, note, existing ->
                        onSaveSettlement(
                            tripId,
                            fromId,
                            toId,
                            amount,
                            currency,
                            note,
                            existing,
                        )
                    },
                )
            }
            composable<SettlementRoute> { entry ->
                val route = entry.toRoute<SettlementRoute>()
                val tripId = UUID.fromString(route.tripId)
                val settlementId = UUID.fromString(route.settlementId)
                LaunchedEffect(tripId) { onTripVisible(tripId) }
                val tripContent = state.tripContent
                    .takeIf { it.tripId == tripId }
                    ?: TripContentUiState(tripId = tripId)
                SettlementDetailScreen(
                    settlement = tripContent.settlements.firstOrNull { it.id == settlementId },
                    people = tripContent.people,
                    onBack = navController::popBackStack,
                    onEdit = {
                        navController.navigate(
                            EditSettlementRoute(route.tripId, route.settlementId),
                        )
                    },
                    onDelete = {
                        onDeleteSettlement(settlementId)
                        navController.popBackStack()
                    },
                )
            }
            composable<EditSettlementRoute> { entry ->
                val route = entry.toRoute<EditSettlementRoute>()
                val tripId = UUID.fromString(route.tripId)
                val settlementId = UUID.fromString(route.settlementId)
                LaunchedEffect(tripId) { onTripVisible(tripId) }
                val tripContent = state.tripContent
                    .takeIf { it.tripId == tripId }
                    ?: TripContentUiState(tripId = tripId)
                SettlementEditorScreen(
                    people = tripContent.people,
                    existing = tripContent.settlements.firstOrNull { it.id == settlementId },
                    suggestion = null,
                    isWorking = state.isWorking,
                    onBack = navController::popBackStack,
                    onSave = { fromId, toId, amount, currency, note, existing ->
                        onSaveSettlement(
                            tripId,
                            fromId,
                            toId,
                            amount,
                            currency,
                            note,
                            existing,
                        )
                    },
                )
            }
            composable<NonGroupExpensePickerRoute> {
                LaunchedEffect(Unit) { onTripVisible(null) }
                NonGroupExpensePickerScreen(
                    knownPeople = state.friends.knownPeople,
                    isWorking = state.isWorking,
                    onBack = navController::popBackStack,
                    onResolve = { participants ->
                        onResolveNonGroup(participants) { tripId ->
                            navController.navigate(NewExpenseRoute(tripId.toString())) {
                                popUpTo<NonGroupExpensePickerRoute> { inclusive = true }
                            }
                        }
                    },
                )
            }
            composable<FriendRoute> { entry ->
                val route = entry.toRoute<FriendRoute>()
                LaunchedEffect(Unit) { onTripVisible(null) }
                FriendDetailScreen(
                    detail = state.friends.details[route.identityKey],
                    onBack = navController::popBackStack,
                    onSettle = { source ->
                        navController.navigate(
                            SettleRoute(
                                tripId = source.containerId.toString(),
                                fromId = source.suggestion.fromUser.toString(),
                                toId = source.suggestion.toUser.toString(),
                                currency = source.suggestion.currency,
                                amount = source.suggestion.amount.toPlainString(),
                            ),
                        )
                    },
                )
            }
                }
            }
        }
    }
}

@Composable
private fun AppNavigationBar(
    currentRoute: String?,
    onOpen: (Any) -> Unit,
) {
    NavigationBar {
        topDestinations.forEach { destination ->
            NavigationBarItem(
                selected = destination.isSelected(currentRoute),
                onClick = { onOpen(destination.route) },
                icon = { Icon(destination.icon, contentDescription = null) },
                label = { Text(destination.label) },
            )
        }
    }
}

@Composable
private fun AppNavigationRail(
    currentRoute: String?,
    onOpen: (Any) -> Unit,
) {
    NavigationRail(modifier = Modifier.fillMaxHeight()) {
        Spacer(modifier = Modifier.weight(1f))
        topDestinations.forEach { destination ->
            NavigationRailItem(
                selected = destination.isSelected(currentRoute),
                onClick = { onOpen(destination.route) },
                icon = { Icon(destination.icon, contentDescription = null) },
                label = { Text(destination.label) },
            )
        }
        Spacer(modifier = Modifier.weight(1f))
    }
}

@Composable
private fun LoadingScreen(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator()
        Text(
            text = "Opening your local data",
            modifier = Modifier.padding(top = 14.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun PlaceholderScreen(
    title: String,
    body: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = title,
            modifier = Modifier.semantics { heading() },
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = body,
            modifier = Modifier.padding(top = 8.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

@Composable
private fun SettingsScreen(
    email: String?,
    isWorking: Boolean,
    onJoinTrip: (String) -> Unit,
    onSignOut: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var confirmSignOut by remember { mutableStateOf(false) }
    var showJoin by remember { mutableStateOf(false) }
    var inviteValue by remember { mutableStateOf("") }
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
    ) {
        Text(
            text = "Settings",
            modifier = Modifier.semantics { heading() },
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = email ?: "Signed in",
            modifier = Modifier.padding(top = 20.dp),
            style = MaterialTheme.typography.titleMedium,
        )
        Text(
            text = "Local Supabase development environment",
            modifier = Modifier.padding(top = 4.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        TextButton(
            onClick = { showJoin = true },
            modifier = Modifier.padding(top = 16.dp),
            enabled = !isWorking,
        ) {
            Text("Join a trip with an invite")
        }
        TextButton(
            onClick = { confirmSignOut = true },
            modifier = Modifier.padding(top = 24.dp),
            enabled = !isWorking,
        ) {
            Text("Sign out")
        }
    }
    if (showJoin) {
        AlertDialog(
            onDismissRequest = { showJoin = false },
            title = { Text("Join a trip") },
            text = {
                androidx.compose.material3.OutlinedTextField(
                    value = inviteValue,
                    onValueChange = { inviteValue = it },
                    label = { Text("Invite link or token") },
                    singleLine = true,
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showJoin = false
                        onJoinTrip(inviteValue)
                    },
                    enabled = inviteValue.isNotBlank(),
                ) {
                    Text("Join")
                }
            },
            dismissButton = {
                TextButton(onClick = { showJoin = false }) { Text("Cancel") }
            },
        )
    }
    if (confirmSignOut) {
        AlertDialog(
            onDismissRequest = { confirmSignOut = false },
            title = { Text("Sign out?") },
            text = { Text("Tab will sync pending work before removing this account's local copy.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmSignOut = false
                        onSignOut()
                    },
                    modifier = Modifier.testTag("confirmSignOut"),
                ) {
                    Text("Sign out")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmSignOut = false }) {
                    Text("Cancel")
                }
            },
        )
    }
}

private fun NavHostController.openTopLevel(route: Any) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) {
            saveState = true
        }
        launchSingleTop = true
        restoreState = true
    }
}

private data class TopDestination(
    val route: Any,
    val label: String,
    val icon: ImageVector,
)

private fun TopDestination.isSelected(currentRoute: String?): Boolean =
    currentRoute == route::class.qualifiedName ||
        (route == TripsRoute && currentRoute == TripRoute::class.qualifiedName)

private val topDestinations = listOf(
    TopDestination(FriendsRoute, "Friends", Icons.Outlined.Groups),
    TopDestination(TripsRoute, "Trips", Icons.Outlined.Luggage),
    TopDestination(ActivityRoute, "Activity", Icons.Outlined.NotificationsNone),
    TopDestination(SettingsRoute, "Settings", Icons.Outlined.Settings),
)

@Serializable
private data object FriendsRoute

@Serializable
private data object TripsRoute

@Serializable
private data object ActivityRoute

@Serializable
private data object SettingsRoute

@Serializable
private data class TripRoute(val id: String)

@Serializable
private data class NewExpenseRoute(val tripId: String)

@Serializable
private data class ExpenseRoute(val tripId: String, val expenseId: String)

@Serializable
private data class EditExpenseRoute(val tripId: String, val expenseId: String)

@Serializable
private data class SettleRoute(
    val tripId: String,
    val fromId: String? = null,
    val toId: String? = null,
    val currency: String? = null,
    val amount: String? = null,
)

private fun SettleRoute.toSuggestion(): SimplifiedDebt? {
    val from = fromId?.let(UUID::fromString) ?: return null
    val to = toId?.let(UUID::fromString) ?: return null
    val code = currency ?: return null
    val value = amount?.let(::BigDecimal) ?: return null
    return SimplifiedDebt(from, to, code, value)
}

@Serializable
private data class SettlementRoute(val tripId: String, val settlementId: String)

@Serializable
private data class EditSettlementRoute(val tripId: String, val settlementId: String)

@Serializable
private data object NonGroupExpensePickerRoute

@Serializable
private data class FriendRoute(val identityKey: String)
