package com.rizzog99.personalfinancetracker.navigation

import androidx.annotation.StringRes
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Insights
import androidx.compose.material.icons.outlined.Category
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.features.activity.ActivityScreen
import com.rizzog99.personalfinancetracker.features.activity.ActivityViewModel
import com.rizzog99.personalfinancetracker.features.activity.TransactionEditorSheet
import com.rizzog99.personalfinancetracker.features.categories.CategorySettingsScreen
import com.rizzog99.personalfinancetracker.features.budgets.BudgetsScreen
import com.rizzog99.personalfinancetracker.features.home.HomeScreen
import com.rizzog99.personalfinancetracker.features.insights.InsightsScreen
import com.rizzog99.personalfinancetracker.features.settings.SettingsSheet
import com.rizzog99.personalfinancetracker.ui.components.AppBackground
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinancePalette
import kotlinx.coroutines.launch

private sealed class MainDestination(
    val route: String,
    @StringRes val labelRes: Int,
) {
    data object Home : MainDestination("home", R.string.tab_home)
    data object Activity : MainDestination("activity", R.string.tab_activity)
    data object Insights : MainDestination("insights", R.string.tab_insights)
    data object Categories : MainDestination("categories", R.string.category_settings_title)
    data object Budgets : MainDestination("budgets", R.string.budgets_title)
}

private val mainDestinations = listOf(
    MainDestination.Home,
    MainDestination.Activity,
    MainDestination.Insights,
)

@Composable
fun PersonalFinanceNavHost() {
    val navController = rememberNavController()
    val currentDestination = navController.currentBackStackEntryAsState().value?.destination
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val palette = LocalFinancePalette.current
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

    AppBackground {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding(),
        ) {
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
                        onViewActivity = {
                            navigateToMainDestination(MainDestination.Activity)
                        },
                        onAddTransaction = {
                            dashboardTransactionEditorVisible = true
                        },
                        onOpenSettings = { settingsVisible = true },
                    )
                }
                composable(MainDestination.Activity.route) {
                    ActivityScreen(onOpenSettings = { settingsVisible = true })
                }
                composable(MainDestination.Insights.route) {
                    InsightsScreen(
                        onAddTransaction = { dashboardTransactionEditorVisible = true },
                        onOpenSettings = { settingsVisible = true },
                    )
                }
                composable(MainDestination.Categories.route) {
                    CategorySettingsScreen(onBack = { navController.popBackStack() })
                }
                composable(MainDestination.Budgets.route) {
                    BudgetsScreen(onBack = { navController.popBackStack() })
                }
            }

            if (settingsVisible) {
                SettingsSheet(
                    onDismiss = { settingsVisible = false },
                    onOpenCategories = {
                        settingsVisible = false
                        navController.navigate(MainDestination.Categories.route)
                    },
                    onOpenBudgets = {
                        settingsVisible = false
                        navController.navigate(MainDestination.Budgets.route)
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
                            }
                        }
                    },
                )
            }

            if (currentDestination?.route in mainDestinations.map(MainDestination::route)) {
                NavigationBar(containerColor = palette.surfaceRaised) {
                    mainDestinations.forEach { destination ->
                        val selected = currentDestination?.hierarchy?.any { it.route == destination.route } == true
                        NavigationBarItem(
                            selected = selected,
                            onClick = {
                                navigateToMainDestination(destination)
                            },
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
    MainDestination.Budgets -> Icons.Outlined.Category
}
