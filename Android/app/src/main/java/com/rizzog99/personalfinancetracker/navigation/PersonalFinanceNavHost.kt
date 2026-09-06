package com.rizzog99.personalfinancetracker.navigation

import androidx.annotation.StringRes
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.features.activity.ActivityScreen
import com.rizzog99.personalfinancetracker.features.categories.CategorySettingsScreen
import com.rizzog99.personalfinancetracker.features.home.HomeScreen
import com.rizzog99.personalfinancetracker.features.settings.SettingsSheet
import com.rizzog99.personalfinancetracker.ui.components.AppBackground
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinancePalette

private sealed class MainDestination(
    val route: String,
    @StringRes val labelRes: Int,
) {
    data object Home : MainDestination("home", R.string.tab_home)
    data object Activity : MainDestination("activity", R.string.tab_activity)
    data object Insights : MainDestination("insights", R.string.tab_insights)
    data object Categories : MainDestination("categories", R.string.category_settings_title)
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
    val palette = LocalFinancePalette.current
    var startCreatingActivity by rememberSaveable { mutableStateOf(false) }
    var returnToDashboardAfterCreation by rememberSaveable { mutableStateOf(false) }
    var settingsVisible by rememberSaveable { mutableStateOf(false) }

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
            ) {
                composable(MainDestination.Home.route) {
                    HomeScreen(
                        onViewActivity = {
                            navController.navigate(MainDestination.Activity.route) {
                                launchSingleTop = true
                            }
                        },
                        onAddTransaction = {
                            startCreatingActivity = true
                            returnToDashboardAfterCreation = true
                            navController.navigate(MainDestination.Activity.route) {
                                launchSingleTop = true
                            }
                        },
                        onOpenSettings = { settingsVisible = true },
                    )
                }
                composable(MainDestination.Activity.route) {
                    ActivityScreen(
                        startCreating = startCreatingActivity,
                        onStartCreatingConsumed = { startCreatingActivity = false },
                        returnToDashboardAfterCreation = returnToDashboardAfterCreation,
                        onDashboardCreationFinished = {
                            returnToDashboardAfterCreation = false
                            navController.navigate(MainDestination.Home.route) {
                                popUpTo(MainDestination.Home.route) { inclusive = false }
                                launchSingleTop = true
                            }
                        },
                    )
                }
                composable(MainDestination.Insights.route) {
                    InsightsPlaceholderScreen()
                }
                composable(MainDestination.Categories.route) {
                    CategorySettingsScreen(onBack = { navController.popBackStack() })
                }
            }

            if (settingsVisible) {
                SettingsSheet(
                    onDismiss = { settingsVisible = false },
                    onOpenCategories = {
                        settingsVisible = false
                        navController.navigate(MainDestination.Categories.route)
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
                                navController.navigate(destination.route) {
                                    popUpTo(navController.graph.startDestinationId) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
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

@Composable
private fun InsightsPlaceholderScreen() {
    Box(modifier = Modifier.fillMaxSize().padding(20.dp)) {
        FinanceCard(modifier = Modifier.align(androidx.compose.ui.Alignment.Center)) {
            Column(
                modifier = Modifier.padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = stringResource(R.string.insights_title),
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    text = stringResource(R.string.foundation_placeholder),
                    style = MaterialTheme.typography.bodyMedium,
                    color = LocalFinancePalette.current.textMid,
                )
            }
        }
    }
}

@Composable
private fun MainDestination.icon() = when (this) {
    MainDestination.Home -> Icons.Outlined.Home
    MainDestination.Activity -> Icons.AutoMirrored.Outlined.List
    MainDestination.Insights -> Icons.Outlined.Insights
    MainDestination.Categories -> Icons.Outlined.Category
}
