package com.rizzog99.personalfinancetracker.navigation

import androidx.annotation.StringRes
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Category
import androidx.compose.material.icons.outlined.DocumentScanner
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Insights
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material.icons.outlined.Savings
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.PermanentDrawerSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.features.activity.ActivityScreen
import com.rizzog99.personalfinancetracker.features.activity.ActivityTwoPaneScreen
import com.rizzog99.personalfinancetracker.features.activity.ActivityViewModel
import com.rizzog99.personalfinancetracker.features.activity.TransactionEditorSheet
import com.rizzog99.personalfinancetracker.features.budgets.BudgetsScreen
import com.rizzog99.personalfinancetracker.features.categories.CategorySettingsScreen
import com.rizzog99.personalfinancetracker.features.data.DataTransferScreen
import com.rizzog99.personalfinancetracker.features.home.HomeScreen
import com.rizzog99.personalfinancetracker.features.insights.InsightsScreen
import com.rizzog99.personalfinancetracker.features.plan.GoalsScreen
import com.rizzog99.personalfinancetracker.features.plan.PlanScreen
import com.rizzog99.personalfinancetracker.features.recurring.RecurringRulesScreen
import com.rizzog99.personalfinancetracker.features.settings.ScanCategoriesRoute
import com.rizzog99.personalfinancetracker.features.settings.SettingsSheet
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import kotlinx.coroutines.launch

private sealed class MainDestination(
    val route: String,
    @StringRes val labelRes: Int,
) {
    data object Home : MainDestination("home", R.string.tab_home)
    data object Activity : MainDestination("activity", R.string.tab_activity)
    data object Plan : MainDestination("plan", R.string.tab_plan)
    data object Insights : MainDestination("insights", R.string.tab_insights)
    data object Recurring : MainDestination("recurring", R.string.recurring_title)
    data object Goals : MainDestination("goals", R.string.goals_title)
    data object Categories : MainDestination("categories", R.string.category_settings_title)
    data object ScanCategories : MainDestination("scan-categories", R.string.scan_categories_title)
    data object Budgets : MainDestination("budgets", R.string.budgets_title)
    data object DataTransfer : MainDestination("data-transfer", R.string.import_export_title)
}

/** Compact bottom bar: iOS `TabItem` (#283, b649dff) — Home · Activity · Plan · Insights. */
private val phoneTabs = listOf(
    MainDestination.Home,
    MainDestination.Activity,
    MainDestination.Plan,
    MainDestination.Insights,
)

/**
 * Wide drawer: iOS `IPadSection.Group` (b649dff) — what the phone stacks on Plan gets its own
 * destination. No Health Score item until #304 (D-03); Settings follows as its own row.
 */
private val drawerGroups: List<Pair<Int?, List<MainDestination>>> = listOf(
    null to listOf(MainDestination.Home, MainDestination.Activity),
    R.string.tab_plan to listOf(MainDestination.Recurring, MainDestination.Budgets, MainDestination.Goals),
    R.string.tab_insights to listOf(MainDestination.Insights),
)
private val drawerDestinations = drawerGroups.flatMap { it.second }

/** Optional args: "See all" passes none, a Coming-up row an id, "Add recurring payment" add=true. */
private const val RECURRING_ROUTE = "recurring?editRuleId={editRuleId}&add={add}"

/** A destination's route without its query arguments. */
private val String.baseRoute get() = substringBefore('?')

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PersonalFinanceNavHost(
    // The only seam #110's tests need: they drive the *production* graph and read its real back
    // queue, instead of rebuilding a test-only graph that could drift away from this one.
    navController: NavHostController = rememberNavController(),
) {
    val currentDestination = navController.currentBackStackEntryAsState().value?.destination
    val currentRoute = currentDestination?.route?.baseRoute
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val transactionEditorViewModel: ActivityViewModel = viewModel(
        factory = ActivityViewModel.factory(
            transactionRepository = application.transactionRepository,
            categoryRepository = application.categoryRepository,
            recurrenceRepository = application.recurrenceRepository,
        ),
    )
    val transactionEditorState by transactionEditorViewModel.uiState.collectAsState()
    val transactionEditorScope = rememberCoroutineScope()
    var dashboardTransactionEditorVisible by rememberSaveable { mutableStateOf(false) }
    var settingsVisible by rememberSaveable { mutableStateOf(false) }
    var tabTransitionDirection by rememberSaveable { mutableStateOf(1) }
    val snackbarHostState = remember { SnackbarHostState() }
    // Compact Activity's own queue, drawn in this Scaffold so Material lifts it above the + (#368).
    // A separate state, not the shell's: on one shared queue, each pending Activity Undo would hold
    // back the shell's "Transaction saved" for its whole 5 s window (#376).
    val activitySnackbarHostState = remember { SnackbarHostState() }

    val systemDark = isSystemInDarkTheme()
    val themeMode by application.preferencesRepository.themeMode.collectAsState(initial = ThemeMode.SYSTEM)
    val isDarkTheme = when (themeMode) {
        ThemeMode.SYSTEM -> systemDark
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    val onToggleTheme: () -> Unit = {
        transactionEditorScope.launch {
            application.preferencesRepository.setThemeMode(if (isDarkTheme) ThemeMode.LIGHT else ThemeMode.DARK)
        }
    }

    // M3's "expanded" width-class breakpoint: a grouped navigation drawer replaces the bottom bar,
    // and the drawer carries the FAB in its header instead of the Scaffold's own FAB slot.
    val isExpandedWidth = LocalConfiguration.current.screenWidthDp >= 840
    val primaryOrder = if (isExpandedWidth) drawerDestinations else phoneTabs

    val navigateToMainDestination: (MainDestination) -> Unit = { destination ->
        if (currentRoute != destination.route) {
            tabTransitionDirection = slideDirection(primaryOrder, currentRoute, destination.route)
            navController.navigate(destination.route) {
                popUpTo(navController.graph.startDestinationId) { saveState = true }
                launchSingleTop = true
                restoreState = true
            }
        }
    }
    val navigateToSecondaryRoute: (String) -> Unit = { route ->
        tabTransitionDirection = 1
        navController.navigate(route) { launchSingleTop = true }
    }
    val navigateBackFromSecondary: () -> Unit = {
        tabTransitionDirection = -1
        navController.popBackStack()
    }
    val savedMessage = stringResource(R.string.transaction_saved)
    // A confirmation only: frozen iOS offers no Undo after a save, and this one never reversed it (#287).
    val onTransactionSaved: () -> Unit = {
        transactionEditorScope.launch {
            snackbarHostState.currentSnackbarData?.dismiss()
            snackbarHostState.showSnackbar(message = savedMessage)
        }
    }
    // Crossing the breakpoint never strands a screen without navigation: Plan keeps the drawer on
    // wide, and the wide-only Goals keeps the bottom bar on compact, under the Plan tab it belongs
    // to. (Recurring and Budgets get their back arrow back on compact instead.)
    val shellRoutes = (if (isExpandedWidth) drawerDestinations + MainDestination.Plan else phoneTabs + MainDestination.Goals).map { it.route }
    val selectedTab = if (currentRoute == MainDestination.Goals.route) MainDestination.Plan.route else currentRoute
    val onMainDestination = currentRoute in shellRoutes && !settingsVisible && !dashboardTransactionEditorVisible
    // Recurring and Budgets are drawer roots on wide (no back arrow, D-05) and pushed screens on phones.
    val secondaryBack: (() -> Unit)? = if (isExpandedWidth) null else navigateBackFromSecondary

    Scaffold(
        snackbarHost = {
            Column {
                SnackbarHost(activitySnackbarHostState)
                SnackbarHost(snackbarHostState) { data -> Snackbar(snackbarData = data) }
            }
        },
        floatingActionButton = {
            if (onMainDestination && !isExpandedWidth) {
                FloatingActionButton(onClick = { dashboardTransactionEditorVisible = true }) {
                    Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_transaction))
                }
            }
        },
        bottomBar = {
            if (onMainDestination && !isExpandedWidth) {
                NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceContainer) {
                    phoneTabs.forEach { destination ->
                        NavigationBarItem(
                            selected = selectedTab == destination.route,
                            onClick = { navigateToMainDestination(destination) },
                            icon = {
                                Icon(
                                    imageVector = destination.icon(),
                                    contentDescription = null,
                                )
                            },
                            label = { Text(stringResource(destination.labelRes)) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                selectedTextColor = MaterialTheme.colorScheme.primary,
                                indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            ),
                            alwaysShowLabel = true,
                        )
                    }
                }
            }
        },
    ) { padding ->
        // Own the system-bar insets here so nested Scaffolds (each screen's own TopAppBar)
        // don't re-apply them and double the top/bottom padding.
        Row(modifier = Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) {
            if (onMainDestination && isExpandedWidth) {
                PermanentDrawerSheet(
                    // ponytail: 240dp, not M3's 360dp default, so Activity's two-pane keeps its room
                    // on an 840–1000dp window; iPad's sidebar is 260pt ideal.
                    modifier = Modifier.width(240.dp).fillMaxHeight().testTag("nav-drawer"),
                    drawerContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                ) {
                    Column(
                        modifier = Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 16.dp),
                    ) {
                        FloatingActionButton(
                            onClick = { dashboardTransactionEditorVisible = true },
                            modifier = Modifier.padding(start = 4.dp, bottom = 12.dp),
                        ) {
                            Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_transaction))
                        }
                        drawerGroups.forEach { (titleRes, destinations) ->
                            titleRes?.let {
                                Text(
                                    text = stringResource(it),
                                    style = MaterialTheme.typography.titleSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier
                                        .padding(start = 16.dp, top = 16.dp, bottom = 8.dp)
                                        .semantics { heading() },
                                )
                            }
                            destinations.forEach { destination ->
                                DrawerItem(
                                    label = stringResource(destination.labelRes),
                                    icon = destination.icon(),
                                    selected = currentRoute == destination.route,
                                    onClick = { navigateToMainDestination(destination) },
                                )
                            }
                        }
                        HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
                        // Android's Settings is a full-screen sheet, so its row opens it (D-04).
                        DrawerItem(
                            label = stringResource(R.string.settings_title),
                            icon = Icons.Outlined.Settings,
                            selected = false,
                            onClick = { settingsVisible = true },
                        )
                    }
                }
            }
        NavHost(
            navController = navController,
            startDestination = MainDestination.Home.route,
            modifier = Modifier.weight(1f),
            enterTransition = {
                slideInHorizontally(
                    initialOffsetX = { width -> tabTransitionDirection * width },
                    animationSpec = tween(durationMillis = 280),
                )
            },
            exitTransition = {
                slideOutHorizontally(
                    targetOffsetX = { width -> -tabTransitionDirection * width },
                    animationSpec = tween(durationMillis = 280),
                )
            },
            popEnterTransition = {
                slideInHorizontally(
                    initialOffsetX = { width -> tabTransitionDirection * width },
                    animationSpec = tween(durationMillis = 280),
                )
            },
            popExitTransition = {
                slideOutHorizontally(
                    targetOffsetX = { width -> -tabTransitionDirection * width },
                    animationSpec = tween(durationMillis = 280),
                )
            },
        ) {
            composable(MainDestination.Home.route) {
                HomeScreen(
                    isDarkTheme = isDarkTheme,
                    onToggleTheme = onToggleTheme,
                    onViewActivity = {
                        navigateToMainDestination(MainDestination.Activity)
                    },
                    onOpenSettings = { settingsVisible = true },
                )
            }
            composable(MainDestination.Activity.route) {
                if (isExpandedWidth) {
                    ActivityTwoPaneScreen(
                        isDarkTheme = isDarkTheme,
                        onToggleTheme = onToggleTheme,
                        onOpenSettings = { settingsVisible = true },
                    )
                } else {
                    ActivityScreen(
                        isDarkTheme = isDarkTheme,
                        onToggleTheme = onToggleTheme,
                        onOpenSettings = { settingsVisible = true },
                        shellSnackbarHostState = activitySnackbarHostState,
                    )
                }
            }
            composable(MainDestination.Plan.route) {
                PlanScreen(
                    isDarkTheme = isDarkTheme,
                    onToggleTheme = onToggleTheme,
                    onOpenSettings = { settingsVisible = true },
                    onOpenRecurring = { navigateToSecondaryRoute(MainDestination.Recurring.route) },
                    onEditRule = { navigateToSecondaryRoute("${MainDestination.Recurring.route}?editRuleId=$it") },
                    onAddRule = { navigateToSecondaryRoute("${MainDestination.Recurring.route}?add=true") },
                    onOpenBudgets = { navigateToSecondaryRoute(MainDestination.Budgets.route) },
                )
            }
            composable(MainDestination.Insights.route) {
                InsightsScreen(
                    isDarkTheme = isDarkTheme,
                    onToggleTheme = onToggleTheme,
                    onOpenSettings = { settingsVisible = true },
                )
            }
            composable(
                route = RECURRING_ROUTE,
                arguments = listOf(
                    navArgument("editRuleId") { type = NavType.StringType; nullable = true; defaultValue = null },
                    navArgument("add") { type = NavType.BoolType; defaultValue = false },
                ),
            ) { entry ->
                RecurringRulesScreen(
                    onBack = secondaryBack,
                    editRuleId = entry.arguments?.getString("editRuleId"),
                    startAdding = entry.arguments?.getBoolean("add") == true,
                )
            }
            composable(MainDestination.Goals.route) {
                GoalsScreen(
                    isDarkTheme = isDarkTheme,
                    onToggleTheme = onToggleTheme,
                    onOpenSettings = { settingsVisible = true },
                )
            }
            composable(MainDestination.Categories.route) {
                CategorySettingsScreen(onBack = navigateBackFromSecondary)
            }
            composable(MainDestination.ScanCategories.route) {
                ScanCategoriesRoute(onBack = navigateBackFromSecondary)
            }
            composable(MainDestination.Budgets.route) {
                BudgetsScreen(onBack = secondaryBack)
            }
            composable(MainDestination.DataTransfer.route) {
                DataTransferScreen(onBack = navigateBackFromSecondary)
            }
        }
        }

        if (settingsVisible) {
            SettingsSheet(
                onDismiss = { settingsVisible = false },
                onOpenCategories = {
                    settingsVisible = false
                    navigateToSecondaryRoute(MainDestination.Categories.route)
                },
                onOpenScanCategories = {
                    settingsVisible = false
                    navigateToSecondaryRoute(MainDestination.ScanCategories.route)
                },
                onOpenDataTransfer = {
                    settingsVisible = false
                    navigateToSecondaryRoute(MainDestination.DataTransfer.route)
                },
            )
        }

        if (dashboardTransactionEditorVisible) {
            TransactionEditorSheet(
                editingTransaction = null,
                categories = transactionEditorState.categories,
                receiptMappingRepository = application.receiptMappingRepository,
                onDismiss = { dashboardTransactionEditorVisible = false },
                onSave = { transaction, recurrenceRule, receiptMerchant ->
                    transactionEditorScope.launch {
                        val saved = recurrenceRule?.let {
                            transactionEditorViewModel.createRecurringTransaction(it)
                        } ?: transactionEditorViewModel.save(transaction)
                        if (saved) {
                            if (receiptMerchant != null && transaction.categoryId != null) {
                                application.receiptMappingRepository.remember(receiptMerchant, transaction.categoryId)
                            }
                            dashboardTransactionEditorVisible = false
                            onTransactionSaved()
                        }
                    }
                },
            )
        }
    }
}

@Composable
private fun DrawerItem(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, selected: Boolean, onClick: () -> Unit) {
    NavigationDrawerItem(
        label = { Text(label) },
        icon = { Icon(icon, contentDescription = null) },
        selected = selected,
        onClick = onClick,
        colors = NavigationDrawerItemDefaults.colors(
            selectedIconColor = MaterialTheme.colorScheme.primary,
            selectedTextColor = MaterialTheme.colorScheme.primary,
            selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
            unselectedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
    )
}

private fun slideDirection(order: List<MainDestination>, fromRoute: String?, toRoute: String?): Int {
    val fromIndex = order.indexOfFirst { it.route == fromRoute }
    val toIndex = order.indexOfFirst { it.route == toRoute }
    return if (fromIndex >= 0 && toIndex >= 0 && toIndex < fromIndex) -1 else 1
}

@Composable
private fun MainDestination.icon() = when (this) {
    MainDestination.Home -> Icons.Outlined.Home
    MainDestination.Activity -> Icons.AutoMirrored.Outlined.List
    MainDestination.Plan -> Icons.Outlined.CalendarMonth
    MainDestination.Insights -> Icons.Outlined.Insights
    MainDestination.Recurring -> Icons.Outlined.Repeat
    MainDestination.Goals -> Icons.Outlined.Flag
    MainDestination.Categories -> Icons.Outlined.Category
    MainDestination.ScanCategories -> Icons.Outlined.DocumentScanner
    MainDestination.Budgets -> Icons.Outlined.Savings
    MainDestination.DataTransfer -> Icons.Outlined.SwapVert
}
