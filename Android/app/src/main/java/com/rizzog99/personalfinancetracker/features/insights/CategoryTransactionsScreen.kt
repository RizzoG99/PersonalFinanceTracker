package com.rizzog99.personalfinancetracker.features.insights

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerType
import com.rizzog99.personalfinancetracker.domain.insights.drillDown
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.activity.ActivityViewModel
import com.rizzog99.personalfinancetracker.features.activity.RecurringEditDialog
import com.rizzog99.personalfinancetracker.features.activity.TransactionEditorSheet
import com.rizzog99.personalfinancetracker.features.activity.TransactionRow
import com.rizzog99.personalfinancetracker.features.travels.TravelChoice
import com.rizzog99.personalfinancetracker.ui.components.EmptyState
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.components.categoryDisplayName
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatTransactionDate
import java.math.BigDecimal
import java.time.LocalDate
import kotlinx.coroutines.launch

/**
 * A category row's drill-down (#303, iOS `CategoryTransactionsView` at b649dff): that category's
 * transactions for the explorer's period and type, grouped by day like Activity, under a summary of
 * what the row said. Rows are derived from [state] on every pass, so an edit saved here shows.
 * Tapping a row edits it with Activity's editor; there is no delete here (D-07).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CategoryTransactionsScreen(drill: ExplorerDrillDown, state: InsightsUiState, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    // Saves go through Activity's model, so recurring "this / this and future" and failures behave as there.
    val activity: ActivityViewModel = viewModel(
        key = "insights-drill-down",
        factory = ActivityViewModel.factory(
            application.transactionRepository,
            application.categoryRepository,
            application.recurrenceRepository,
            application.travelRepository,
        ),
    )
    val activityState by activity.uiState.collectAsState()
    val error by activity.error.collectAsState()
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var editing by remember { mutableStateOf<FinanceTransaction?>(null) }
    var recurringEdit by remember { mutableStateOf<FinanceTransaction?>(null) }
    val updated = stringResource(R.string.transaction_updated)
    // D-11: a failed write is reported as Activity reports it, then cleared.
    val errorText = error?.let { stringResource(it) }
    LaunchedEffect(errorText) {
        if (errorText != null) {
            snackbar.showSnackbar(errorText)
            activity.clearError()
        }
    }

    val period = drill.period
    val periodLabel = explorerPeriodLabel(period, state.zoneId)
    val items = drillDown(state.transactions, drill.label, period, drill.type)
    val title = categoryDisplayName(drill.label)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
        containerColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) { padding ->
        if (items.isEmpty()) {
            EmptyState(
                title = stringResource(R.string.explorer_drill_empty_title),
                message = stringResource(R.string.explorer_drill_empty_message, periodLabel),
                modifier = Modifier.padding(padding).fillMaxSize(),
            )
        } else {
            val total = items.fold(BigDecimal.ZERO) { sum, item -> sum + item.amount.abs() }
            val kind = stringResource(if (drill.type == ExplorerType.INCOME) R.string.explorer_income else R.string.explorer_expenses)
            val today = LocalDate.now(state.zoneId)
            val days = items.groupBy { it.timestamp.atZone(state.zoneId).toLocalDate() }.toList()
            LazyColumn(
                modifier = Modifier.padding(padding),
                contentPadding = PaddingValues(start = 16.dp, top = 8.dp, end = 16.dp, bottom = 112.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                item(key = "summary") {
                    FinanceCard(modifier = Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}) {
                        Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                stringResource(R.string.explorer_drill_summary, kind, periodLabel),
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(formatCurrency(total, state.currencyCode), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                            Text(
                                pluralStringResource(R.plurals.explorer_transactions, items.size, items.size),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                // Same day headers as Activity, so this reads as a filtered slice of that list.
                days.forEach { (day, rows) ->
                    item(key = "day-$day") {
                        Column {
                            Text(
                                text = when (day) {
                                    today -> stringResource(R.string.date_group_today)
                                    today.minusDays(1) -> stringResource(R.string.date_group_yesterday)
                                    else -> formatTransactionDate(rows.first().timestamp)
                                },
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.padding(bottom = 4.dp).semantics { heading() },
                            )
                            rows.forEach { transaction ->
                                TransactionRow(
                                    transaction = transaction,
                                    categories = activityState.categories,
                                    onEdit = { editing = transaction },
                                    onDelete = {},
                                    swipeToDelete = false,
                                    selectable = false,
                                    travel = transaction.travelId?.let { id -> activityState.travels.firstOrNull { it.id == id } },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    editing?.let { transaction ->
        TransactionEditorSheet(
            editingTransaction = transaction,
            categories = activityState.categories,
            receiptMappingRepository = application.receiptMappingRepository,
            travelChoice = TravelChoice(activityState.travels, onCreate = activity::addTravel),
            onDismiss = { editing = null },
            onSave = { saved, _, _ ->
                if (transaction.recurrenceRuleId != null) {
                    recurringEdit = saved
                } else {
                    scope.launch {
                        if (activity.save(saved)) {
                            editing = null
                            snackbar.showSnackbar(updated)
                        }
                    }
                }
            },
        )
    }
    recurringEdit?.let { saved ->
        RecurringEditDialog(
            onDismiss = { recurringEdit = null },
            onEditThisOnly = {
                recurringEdit = null
                scope.launch {
                    if (activity.save(saved)) {
                        editing = null
                        snackbar.showSnackbar(updated)
                    }
                }
            },
            onEditThisAndFuture = {
                recurringEdit = null
                scope.launch {
                    if (activity.updateThisAndFuture(saved)) {
                        editing = null
                        snackbar.showSnackbar(updated)
                    }
                }
            },
        )
    }
}
