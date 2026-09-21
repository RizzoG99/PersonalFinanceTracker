package com.rizzog99.personalfinancetracker.navigation

import androidx.annotation.StringRes
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Insights
import androidx.compose.material.icons.outlined.Savings
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material.icons.outlined.Category
import androidx.compose.material.icons.outlined.DocumentScanner
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.features.activity.ActivityScreen
import com.rizzog99.personalfinancetracker.features.activity.ActivityTwoPaneScreen
import com.rizzog99.personalfinancetracker.features.activity.ActivityViewModel
import com.rizzog99.personalfinancetracker.features.activity.TransactionEditorSheet
import com.rizzog99.personalfinancetracker.features.categories.CategorySettingsScreen
import com.rizzog99.personalfinancetracker.features.settings.ScanCategoriesRoute
import com.rizzog99.personalfinancetracker.features.budgets.BudgetsScreen
import com.rizzog99.personalfinancetracker.features.data.DataTransferScreen
import com.rizzog99.personalfinancetracker.features.home.HomeScreen
import com.rizzog99.personalfinancetracker.features.insights.InsightsScreen
import com.rizzog99.personalfinancetracker.features.settings.SettingsSheet
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import kotlinx.coroutines.launch

private sealed class MainDestination(
    val route: String,
    @StringRes val labelRes: Int,
) {
    data object Home : MainDestination("home", R.string.tab_home)
    data object Activity : MainDestination("activity", R.string.tab_activity)
    data object Insights : MainDestination("insights", R.string.tab_insights)
    data object Categories : MainDestination("categories", R.string.category_settings_title)
    data object ScanCategories : MainDestination("scan-categories", R.string.scan_categories_title)
    data object Budgets : MainDestination("budgets", R.string.budgets_title)
    data object DataTransfer : MainDestination("data-transfer", R.string.import_export_title)
}

private val mainDestinations = listOf(
    MainDestination.Home,
    MainDestination.Activity,
    MainDestination.Insights,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PersonalFinanceNavHost(
    // The only seam #110's tests need: they drive the *production* graph and read its real back
    // queue, instead of rebuilding a test-only graph that could drift away from this one.
    navController: NavHostController = rememberNavController(),
) {
    val currentDestination = navController.currentBackStackEntryAsState().value?.destination
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

    val navigateToMainDestination: (MainDestination) -> Unit = { destination ->
        val currentRoute = currentDestination?.route
        if (currentRoute != destination.route) {
            tabTransitionDirection = tabSlideDirection(currentRoute, destination.route)
            navController.navigate(destination.route) {
                popUpTo(navController.graph.startDestinationId) { saveState = true }
                launchSingleTop = true
                restoreState = true
            }
        }
    }
    val navigateToSecondaryDestination: (MainDestination) -> Unit = { destination ->
        tabTransitionDirection = 1
        navController.navigate(destination.route) { launchSingleTop = true }
    }
    val navigateBackFromSecondary: () -> Unit = {
        tabTransitionDirection = -1
        navController.popBackStack()
    }
    val savedMessage = stringResource(R.string.transaction_saved)
    val undoLabel = stringResource(R.string.undo)
    val onTransactionSaved: () -> Unit = {
        transactionEditorScope.launch {
            snackbarHostState.currentSnackbarData?.dismiss()
            snackbarHostState.showSnackbar(message = savedMessage, actionLabel = undoLabel, duration = androidx.compose.material3.SnackbarDuration.Short)
        }
    }
    val onMainDestination = currentDestination?.route in mainDestinations.map(MainDestination::route) &&
        !settingsVisible && !dashboardTransactionEditorVisible
    // M3's "expanded" width-class breakpoint: a navigation rail replaces the bottom bar, and the
    // rail carries the FAB in its header instead of the Scaffold's own FAB slot.
    val isExpandedWidth = LocalConfiguration.current.screenWidthDp >= 840

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) { data -> Snackbar(snackbarData = data) } },
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
                    mainDestinations.forEach { destination ->
                        val selected = currentDestination?.hierarchy?.any { it.route == destination.route } == true
                        NavigationBarItem(
                            selected = selected,
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
                NavigationRail(
                    modifier = Modifier.fillMaxHeight(),
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                    header = {
                        FloatingActionButton(onClick = { dashboardTransactionEditorVisible = true }) {
                            Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_transaction))
                        }
                    },
                ) {
                    mainDestinations.forEach { destination ->
                        val selected = currentDestination?.hierarchy?.any { it.route == destination.route } == true
                        androidx.compose.material3.NavigationRailItem(
                            selected = selected,
                            onClick = { navigateToMainDestination(destination) },
                            icon = { Icon(imageVector = destination.icon(), contentDescription = null) },
                            label = { Text(stringResource(destination.labelRes)) },
                            colors = NavigationRailItemDefaults.colors(
                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                selectedTextColor = MaterialTheme.colorScheme.primary,
                                indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            ),
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
                    )
                }
            }
            composable(MainDestination.Insights.route) {
                InsightsScreen(
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
                BudgetsScreen(onBack = navigateBackFromSecondary)
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
                    navigateToSecondaryDestination(MainDestination.Categories)
                },
                onOpenScanCategories = {
                    settingsVisible = false
                    navigateToSecondaryDestination(MainDestination.ScanCategories)
                },
                onOpenBudgets = {
                    settingsVisible = false
                    navigateToSecondaryDestination(MainDestination.Budgets)
                },
                onOpenDataTransfer = {
                    settingsVisible = false
                    navigateToSecondaryDestination(MainDestination.DataTransfer)
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

private fun tabSlideDirection(fromRoute: String?, toRoute: String?): Int {
    val fromIndex = mainDestinations.indexOfFirst { it.route == fromRoute }
    val toIndex = mainDestinations.indexOfFirst { it.route == toRoute }
    return if (fromIndex >= 0 && toIndex >= 0 && toIndex < fromIndex) -1 else 1
}

@Composable
private fun MainDestination.icon() = when (this) {
    MainDestination.Home -> Icons.Outlined.Home
    MainDestination.Activity -> Icons.AutoMirrored.Outlined.List
    MainDestination.Insights -> Icons.Outlined.Insights
    MainDestination.Categories -> Icons.Outlined.Category
    MainDestination.ScanCategories -> Icons.Outlined.DocumentScanner
    MainDestination.Budgets -> Icons.Outlined.Savings
    MainDestination.DataTransfer -> Icons.Outlined.SwapVert
}
