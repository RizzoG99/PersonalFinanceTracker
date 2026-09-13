package com.rizzog99.personalfinancetracker.features.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.categories.categoryColor
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.components.LoadingState
import com.rizzog99.personalfinancetracker.ui.components.MainTopBar
import com.rizzog99.personalfinancetracker.ui.components.categoryIconFor
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatPeriod
import com.rizzog99.personalfinancetracker.ui.formatters.formatSignedCurrency
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinanceExtendedColors
import androidx.compose.ui.text.font.FontWeight
import java.math.BigDecimal
import java.time.LocalTime
import kotlinx.coroutines.launch

@Composable
fun HomeScreen(
    isDarkTheme: Boolean,
    onToggleTheme: () -> Unit,
    onViewActivity: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    val application = androidx.compose.ui.platform.LocalContext.current.applicationContext as PersonalFinanceApplication
    val viewModel: HomeViewModel = viewModel(
        factory = HomeViewModel.factory(
            transactionRepository = application.transactionRepository,
            preferencesRepository = application.preferencesRepository,
            categoryRepository = application.categoryRepository,
        ),
    )
    val state by viewModel.uiState.collectAsState()
    val hideBalance by application.preferencesRepository.hideBalance.collectAsState(initial = false)
    val scope = rememberCoroutineScope()

    // POST_NOTIFICATIONS is a runtime permission from API 33 (Tiramisu); below that it's
    // implicitly granted. Without it, WorkManager would enqueue a worker that can never
    // actually post the reminder — request it before scheduling, not after.
    val notificationPermissionLauncher = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            application.scheduleDailyReminder()
            scope.launch { application.preferencesRepository.setDailyReminderEnabled(true) }
        }
    }
    val onSetDailyReminder: () -> Unit = {
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            androidx.core.content.ContextCompat.checkSelfPermission(
                application,
                android.Manifest.permission.POST_NOTIFICATIONS,
            ) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        } else {
            application.scheduleDailyReminder()
            scope.launch { application.preferencesRepository.setDailyReminderEnabled(true) }
        }
    }

    Scaffold(
        topBar = {
            MainTopBar(
                title = stringResource(R.string.home_title),
                isDarkTheme = isDarkTheme,
                onToggleTheme = onToggleTheme,
                onOpenSettings = onOpenSettings,
                screenActions = {
                    IconButton(onClick = {
                        scope.launch { application.preferencesRepository.setHideBalance(!hideBalance) }
                    }) {
                        Icon(
                            imageVector = if (hideBalance) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                            contentDescription = stringResource(if (hideBalance) R.string.show_balance else R.string.hide_balance),
                        )
                    }
                },
            )
        },
        containerColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) { innerPadding ->
        when {
            state.isLoading -> LoadingState(modifier = Modifier.padding(innerPadding))
            else -> HomeContent(
                state = state,
                hideBalance = hideBalance,
                onViewActivity = onViewActivity,
                onSetDailyReminder = onSetDailyReminder,
                onDismissPrompt = {
                    scope.launch { application.preferencesRepository.setPulsePromptDismissed(true) }
                },
                modifier = Modifier.padding(innerPadding),
            )
        }
    }
}

@Composable
private fun HomeContent(
    state: HomeUiState,
    hideBalance: Boolean,
    onViewActivity: () -> Unit,
    onSetDailyReminder: () -> Unit,
    onDismissPrompt: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val metrics = requireNotNull(state.metrics)
    val period = requireNotNull(state.period)
    val pulseMetrics = requireNotNull(state.pulseMetrics)
    val greeting = when (LocalTime.now().hour) {
        in 5..11 -> R.string.greeting_morning
        in 12..17 -> R.string.greeting_afternoon
        else -> R.string.greeting_evening
    }
    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(PaddingValues(horizontal = 20.dp, vertical = 16.dp)),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = stringResource(greeting),
            style = MaterialTheme.typography.bodyLarge,
        )
        BalanceCard(
            totalBalance = formatCurrency(metrics.totalBalance, state.currencyCode),
            periodLabel = formatPeriod(period.start, period.endInclusive),
            income = metrics.periodIncome,
            expenses = metrics.periodExpenses,
            currencyCode = state.currencyCode,
            hideBalance = hideBalance,
        )
        FinancialPulseCard(
            metrics = pulseMetrics,
            dailyReminderEnabled = state.dailyReminderEnabled,
            pulsePromptDismissed = state.pulsePromptDismissed,
            onSetDailyReminder = onSetDailyReminder,
            onDismissPrompt = onDismissPrompt,
        )
        if (metrics.recentTransactions.isEmpty()) {
            EmptyDashboardCard(onViewActivity = onViewActivity)
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = stringResource(R.string.recent_transactions).uppercase(),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f).semantics { heading() },
                    )
                    TextButton(onClick = onViewActivity) { Text(stringResource(R.string.view_activity)) }
                }
                RecentTransactionsCard(
                    transactions = metrics.recentTransactions,
                    categories = state.categories,
                )
            }
        }
    }
}

@Composable
private fun BalanceCard(
    totalBalance: String,
    periodLabel: String,
    income: java.math.BigDecimal,
    expenses: java.math.BigDecimal,
    currencyCode: String,
    hideBalance: Boolean,
) {
    val useVerticalStats = LocalDensity.current.fontScale >= 1.3f
    val placeholder = stringResource(R.string.balance_hidden_placeholder)
    FinanceCard(containerColor = MaterialTheme.colorScheme.primaryContainer) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = stringResource(R.string.total_balance),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(
                text = if (hideBalance) placeholder else totalBalance,
                style = MaterialTheme.typography.displayMedium,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            Text(
                text = periodLabel,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary,
            )
            if (useVerticalStats) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    PeriodStats(
                        income = income,
                        expenses = expenses,
                        currencyCode = currencyCode,
                        hideBalance = hideBalance,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            } else {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    PeriodStats(
                        income = income,
                        expenses = expenses,
                        currencyCode = currencyCode,
                        hideBalance = hideBalance,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

@Composable
private fun PeriodStats(
    income: BigDecimal,
    expenses: BigDecimal,
    currencyCode: String,
    hideBalance: Boolean,
    modifier: Modifier,
) {
    val placeholder = stringResource(R.string.balance_hidden_placeholder)
    FinancialStat(
        modifier = modifier,
        label = stringResource(R.string.filter_income),
        value = if (hideBalance) placeholder else formatSignedCurrency(income, currencyCode),
        contentColor = LocalFinanceExtendedColors.current.positive,
        containerColor = LocalFinanceExtendedColors.current.positiveContainer,
        icon = { Icon(Icons.Outlined.ArrowDownward, contentDescription = null, modifier = Modifier.size(18.dp)) },
    )
    FinancialStat(
        modifier = modifier,
        label = stringResource(R.string.filter_expense),
        value = when {
            hideBalance -> placeholder
            expenses.signum() == 0 -> formatCurrency(BigDecimal.ZERO, currencyCode)
            else -> formatSignedCurrency(expenses.negate(), currencyCode)
        },
        contentColor = LocalFinanceExtendedColors.current.negative,
        containerColor = LocalFinanceExtendedColors.current.negativeContainer,
        valueColor = if (expenses.signum() == 0) MaterialTheme.colorScheme.onSurfaceVariant else LocalFinanceExtendedColors.current.negative,
        icon = { Icon(Icons.Outlined.ArrowUpward, contentDescription = null, modifier = Modifier.size(18.dp)) },
    )
}

@Composable
private fun FinancialStat(
    label: String,
    value: String,
    contentColor: androidx.compose.ui.graphics.Color,
    containerColor: androidx.compose.ui.graphics.Color,
    valueColor: androidx.compose.ui.graphics.Color = contentColor,
    icon: @Composable () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier = modifier
            .background(containerColor, shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            androidx.compose.runtime.CompositionLocalProvider(
                androidx.compose.material3.LocalContentColor provides contentColor,
                content = icon,
            )
            Text(label, style = MaterialTheme.typography.titleSmall, color = contentColor)
        }
        Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = valueColor)
    }
}

@Composable
private fun EmptyDashboardCard(onViewActivity: () -> Unit) {
    FinanceCard {
        Column(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = stringResource(R.string.empty_dashboard_title),
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.semantics { heading() },
            )
            Text(stringResource(R.string.empty_dashboard_message), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = onViewActivity) { Text(stringResource(R.string.go_to_activity)) }
        }
    }
}

@Composable
private fun RecentTransactionsCard(
    transactions: List<FinanceTransaction>,
    categories: List<FinanceCategory>,
) {
    FinanceCard {
        Column(modifier = Modifier.fillMaxWidth().padding(20.dp)) {
            transactions.forEachIndexed { index, transaction ->
                if (index > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                val category = categories.firstOrNull { it.id == transaction.categoryId }
                RecentTransactionRow(transaction, category)
            }
        }
    }
}

@Composable
private fun RecentTransactionRow(transaction: FinanceTransaction, category: FinanceCategory?) {
    val isIncome = transaction.amount >= java.math.BigDecimal.ZERO
    val categoryColor = categoryColor(category?.colorToken ?: "categoryGray")
    val categoryIcon = categoryIconFor(category?.iconToken ?: "")
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(categoryColor.copy(alpha = 0.14f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = categoryIcon,
                contentDescription = null,
                tint = categoryColor,
                modifier = Modifier.size(24.dp),
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(transaction.note.ifBlank { transaction.categoryLabel }, style = MaterialTheme.typography.bodyLarge)
            Text(
                text = transaction.categoryLabel,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.width(12.dp))
        Text(
            text = formatSignedCurrency(transaction.amount, transaction.currencyCode),
            style = MaterialTheme.typography.titleSmall,
            color = if (isIncome) LocalFinanceExtendedColors.current.positive else LocalFinanceExtendedColors.current.negative,
        )
    }
}
