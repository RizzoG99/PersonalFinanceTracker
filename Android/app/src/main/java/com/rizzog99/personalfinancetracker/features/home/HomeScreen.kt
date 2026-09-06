package com.rizzog99.personalfinancetracker.features.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Settings
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.components.LoadingState
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatPeriod
import com.rizzog99.personalfinancetracker.ui.formatters.formatSignedCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatTransactionDate
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinancePalette
import java.math.BigDecimal
import java.time.LocalTime

@Composable
fun HomeScreen(
    onViewActivity: () -> Unit,
    onAddTransaction: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    val application = androidx.compose.ui.platform.LocalContext.current.applicationContext as PersonalFinanceApplication
    val viewModel: HomeViewModel = viewModel(
        factory = HomeViewModel.factory(
            transactionRepository = application.transactionRepository,
            preferencesRepository = application.preferencesRepository,
        ),
    )
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        containerColor = androidx.compose.ui.graphics.Color.Transparent,
        contentColor = MaterialTheme.colorScheme.onBackground,
    ) { innerPadding ->
        when {
            state.isLoading -> LoadingState(modifier = Modifier.padding(innerPadding))
            else -> HomeContent(
                state = state,
                onViewActivity = onViewActivity,
                onAddTransaction = onAddTransaction,
                onOpenSettings = onOpenSettings,
                modifier = Modifier.padding(innerPadding),
            )
        }
    }
}

@Composable
private fun HomeContent(
    state: HomeUiState,
    onViewActivity: () -> Unit,
    onAddTransaction: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val metrics = requireNotNull(state.metrics)
    val period = requireNotNull(state.period)
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
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            IconButton(onClick = onOpenSettings) {
                Icon(
                    imageVector = Icons.Outlined.Settings,
                    contentDescription = stringResource(R.string.settings_title),
                )
            }
            IconButton(onClick = onAddTransaction) {
                Icon(
                    imageVector = Icons.Outlined.Add,
                    contentDescription = stringResource(R.string.add_transaction),
                )
            }
        }
        Text(
            text = stringResource(greeting),
            style = MaterialTheme.typography.displaySmall,
            modifier = Modifier.semantics { heading() },
        )
        BalanceCard(
            totalBalance = formatCurrency(metrics.totalBalance, state.currencyCode),
            periodLabel = formatPeriod(period.start, period.endInclusive),
            income = metrics.periodIncome,
            expenses = metrics.periodExpenses,
            currencyCode = state.currencyCode,
        )
        if (metrics.recentTransactions.isEmpty()) {
            EmptyDashboardCard(onViewActivity = onViewActivity)
        } else {
            RecentTransactionsCard(
                transactions = metrics.recentTransactions,
                onViewActivity = onViewActivity,
            )
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
) {
    val palette = LocalFinancePalette.current
    val hasPeriodTransactions = income.signum() != 0 || expenses.signum() != 0
    val useVerticalStats = LocalDensity.current.fontScale >= 1.3f
    FinanceCard {
        Column(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = stringResource(R.string.total_balance),
                style = MaterialTheme.typography.titleSmall,
                color = palette.textMid,
            )
            Text(
                text = totalBalance,
                style = MaterialTheme.typography.displaySmall,
                fontFamily = FontFamily.Monospace,
            )
            HorizontalDivider(color = palette.hairline)
            Text(
                text = stringResource(R.string.current_financial_period),
                style = MaterialTheme.typography.labelMedium,
                color = palette.textDim,
            )
            Text(
                text = periodLabel,
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textMid,
            )
            if (hasPeriodTransactions) {
                if (useVerticalStats) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        PeriodStats(
                            income = income,
                            expenses = expenses,
                            currencyCode = currencyCode,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                } else {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        PeriodStats(
                            income = income,
                            expenses = expenses,
                            currencyCode = currencyCode,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            } else {
                Text(
                    text = stringResource(R.string.no_transactions_this_period),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textMid,
                )
            }
        }
    }
}

@Composable
private fun PeriodStats(
    income: BigDecimal,
    expenses: BigDecimal,
    currencyCode: String,
    modifier: Modifier,
) {
    val palette = LocalFinancePalette.current
    FinancialStat(
        modifier = modifier,
        label = stringResource(R.string.filter_income),
        value = formatSignedCurrency(income, currencyCode),
        color = palette.positive,
        icon = { Icon(Icons.Outlined.ArrowDownward, contentDescription = null) },
    )
    FinancialStat(
        modifier = modifier,
        label = stringResource(R.string.filter_expense),
        value = if (expenses.signum() == 0) {
            formatCurrency(BigDecimal.ZERO, currencyCode)
        } else {
            formatSignedCurrency(expenses.negate(), currencyCode)
        },
        color = palette.negative,
        valueColor = if (expenses.signum() == 0) palette.textMid else palette.negative,
        icon = { Icon(Icons.Outlined.ArrowUpward, contentDescription = null) },
    )
}

@Composable
private fun FinancialStat(
    label: String,
    value: String,
    color: androidx.compose.ui.graphics.Color,
    valueColor: androidx.compose.ui.graphics.Color = color,
    icon: @Composable () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier = modifier
            .border(1.dp, color.copy(alpha = 0.38f), shape)
            .background(color.copy(alpha = 0.14f), shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            androidx.compose.runtime.CompositionLocalProvider(
                androidx.compose.material3.LocalContentColor provides color,
                content = icon,
            )
            Text(label, style = MaterialTheme.typography.titleSmall, color = color)
        }
        Text(value, style = MaterialTheme.typography.titleMedium, color = valueColor, fontFamily = FontFamily.Monospace)
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
            Text(stringResource(R.string.empty_dashboard_message), color = LocalFinancePalette.current.textMid)
            Button(onClick = onViewActivity) { Text(stringResource(R.string.go_to_activity)) }
        }
    }
}

@Composable
private fun RecentTransactionsCard(
    transactions: List<FinanceTransaction>,
    onViewActivity: () -> Unit,
) {
    FinanceCard {
        Column(modifier = Modifier.fillMaxWidth().padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = stringResource(R.string.recent_transactions),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                TextButton(onClick = onViewActivity) { Text(stringResource(R.string.view_activity)) }
            }
            Spacer(Modifier.height(4.dp))
            transactions.forEachIndexed { index, transaction ->
                if (index > 0) HorizontalDivider(color = LocalFinancePalette.current.hairline)
                RecentTransactionRow(transaction)
            }
        }
    }
}

@Composable
private fun RecentTransactionRow(transaction: FinanceTransaction) {
    val palette = LocalFinancePalette.current
    val isIncome = transaction.amount >= java.math.BigDecimal.ZERO
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(transaction.note.ifBlank { transaction.categoryLabel }, style = MaterialTheme.typography.bodyLarge)
            Text(
                text = "${transaction.categoryLabel} · ${formatTransactionDate(transaction.timestamp)}",
                style = MaterialTheme.typography.bodySmall,
                color = palette.textMid,
            )
        }
        Spacer(Modifier.width(12.dp))
        Text(
            text = formatSignedCurrency(transaction.amount, transaction.currencyCode),
            style = MaterialTheme.typography.titleSmall,
            color = if (isIncome) palette.positive else palette.negative,
            fontFamily = FontFamily.Monospace,
        )
    }
}
