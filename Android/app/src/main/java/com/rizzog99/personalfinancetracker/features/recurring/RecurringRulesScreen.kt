package com.rizzog99.personalfinancetracker.features.recurring

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.activity.TransactionEditorSheet
import com.rizzog99.personalfinancetracker.features.categories.categoryColor
import com.rizzog99.personalfinancetracker.ui.components.EmptyState
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.components.LoadingState
import com.rizzog99.personalfinancetracker.ui.components.categoryIconFor
import com.rizzog99.personalfinancetracker.ui.formatters.formatSignedCurrency
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinanceExtendedColors
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.launch

/**
 * Every recurring *rule* — not the transactions it produced (#294, iOS `RecurringView.swift` at b649dff):
 * tap a rule to edit its template, swipe (or TalkBack's "Stop") to stop it, "+" to add one.
 *
 * [editRuleId] opens that rule's editor on entry — Plan's "Coming up" rows (iOS `PlanView.swift:198`).
 * The route, Plan's "See all" and the wide-layout destination are wired by #283.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecurringRulesScreen(
    /** `null` on the wide layout, where Recurring is a drawer root with no back arrow (#283 D-05). */
    onBack: (() -> Unit)?,
    editRuleId: String? = null,
    clock: Clock = Clock.systemDefaultZone(),
    /** Plan's "Add recurring payment" opens the add editor on entry (#283, iOS `presetRecurring`). */
    startAdding: Boolean = false,
) {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val viewModel: RecurringRulesViewModel = viewModel(
        factory = RecurringRulesViewModel.factory(
            recurrenceRepository = application.recurrenceRepository,
            transactionRepository = application.transactionRepository,
            categoryRepository = application.categoryRepository,
            clock = clock,
            receiptMappingRepository = application.receiptMappingRepository,
        ),
    )
    val state by viewModel.uiState.collectAsState()
    val error by viewModel.error.collectAsState()
    var editingRuleId by rememberSaveable { mutableStateOf(editRuleId) }
    var adding by rememberSaveable { mutableStateOf(startAdding) }
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val errorMessage = error?.let { stringResource(it) }
    LaunchedEffect(errorMessage) {
        if (errorMessage != null) {
            snackbarHostState.showSnackbar(errorMessage)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.recurring_title), modifier = Modifier.semantics { heading() }) },
                navigationIcon = {
                    if (onBack != null) {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back))
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { adding = true }) {
                        Icon(Icons.Outlined.Add, stringResource(R.string.recurring_add))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                    navigationIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) { padding ->
        RecurringRulesContent(
            state = state,
            zoneId = clock.zone,
            onSelect = { editingRuleId = it.id },
            onStop = viewModel::stop,
            modifier = Modifier.padding(padding),
        )
    }

    // A rule that is not (or no longer) active has nothing to open; the id is kept until it loads.
    val editingRule = state.rows.firstOrNull { it.rule.id == editingRuleId }?.rule
    if (editingRule != null) {
        TransactionEditorSheet(
            editingTransaction = editingRule.asEditorTransaction(),
            categories = state.categories,
            receiptMappingRepository = application.receiptMappingRepository,
            onDismiss = { editingRuleId = null },
            onSave = { edited, _, _ ->
                scope.launch { if (viewModel.saveRule(editingRule, edited)) editingRuleId = null }
            },
            ruleCadence = cadenceLabel(editingRule.frequency, editingRule.interval),
        )
    } else if (!state.isLoading && editingRuleId != null && state.rows.none { it.rule.id == editingRuleId }) {
        LaunchedEffect(Unit) { editingRuleId = null }
    }
    if (adding) {
        TransactionEditorSheet(
            editingTransaction = null,
            categories = state.categories,
            receiptMappingRepository = application.receiptMappingRepository,
            onDismiss = { adding = false },
            onSave = { transaction, newRule, merchant ->
                scope.launch { if (viewModel.add(transaction, newRule, merchant)) adding = false }
            },
            presetRepeats = true,
        )
    }
}

/** The rule as the editor's form values: its template, dated at its start (shown read-only). */
private fun RecurrenceRule.asEditorTransaction() = FinanceTransaction(
    id = id,
    timestamp = startDate,
    amount = amount,
    note = note,
    categoryLabel = categoryLabel,
    categoryId = categoryId,
    currencyCode = currencyCode,
    goalId = goalId,
    recurrenceRuleId = null,
)

/** Stat cards, rows, empty state. Stateless, so the capture matrix hosts exactly this. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun RecurringRulesContent(
    state: RecurringRulesUiState,
    zoneId: ZoneId,
    onSelect: (RecurrenceRule) -> Unit,
    onStop: (RecurrenceRule) -> Unit,
    modifier: Modifier = Modifier,
) {
    when {
        state.isLoading -> LoadingState(modifier.fillMaxSize())
        state.rows.isEmpty() -> EmptyState(
            title = stringResource(R.string.recurring_empty_title),
            message = stringResource(R.string.recurring_empty_detail),
            modifier = modifier.padding(vertical = 56.dp),
        )
        else -> LazyColumn(
            modifier = modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            item {
                FlowRow(
                    modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    maxItemsInEachRow = 2,
                ) {
                    StatCard(stringResource(R.string.recurring_active), state.activeCount.toString(), null, Modifier.weight(1f))
                    StatCard(
                        stringResource(R.string.recurring_monthly_spend),
                        formatSignedCurrency(state.monthlySpend, "EUR"),
                        LocalFinanceExtendedColors.current.negative,
                        Modifier.weight(1f),
                    )
                }
            }
            // Keyed, so a stopped row's swipe state is not handed to the row that takes its place.
            items(state.rows, key = { it.rule.id }) { row ->
                RuleRow(row = row, zoneId = zoneId, onSelect = { onSelect(row.rule) }, onStop = { onStop(row.rule) })
            }
        }
    }
}

@Composable
private fun StatCard(label: String, value: String, valueColor: androidx.compose.ui.graphics.Color?, modifier: Modifier) {
    FinanceCard(modifier = modifier.semantics(mergeDescendants = true) {}) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                value,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                color = valueColor ?: MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun RuleRow(row: RecurringRuleRow, zoneId: ZoneId, onSelect: () -> Unit, onStop: () -> Unit) {
    val rule = row.rule
    val stopLabel = stringResource(R.string.recurring_stop)
    // Same swipe as Activity's rows (springs back; the row leaves only when the rule is gone from
    // state), but Stop is immediate: frozen iOS asks nothing and offers no Undo here (D-01).
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) onStop()
            false
        },
    )
    val categoryTint = categoryColor(row.category?.colorToken ?: "categoryGray")
    val amountColor = if (rule.amount < BigDecimal.ZERO) LocalFinanceExtendedColors.current.negative else LocalFinanceExtendedColors.current.positive
    val cadence = cadenceLabel(rule.frequency, rule.interval)
    val subtitle = row.nextDate?.let { "$cadence · ${stringResource(R.string.recurring_next, formatRuleDate(it, zoneId))}" } ?: cadence

    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.errorContainer, RoundedCornerShape(12.dp))
                    .padding(horizontal = 20.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Icon(Icons.Outlined.EventBusy, contentDescription = null, tint = MaterialTheme.colorScheme.onErrorContainer)
            }
        },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .testTag("recurringRule-${rule.id}")
                // Opaque: it sits over the swipe's red background.
                .background(MaterialTheme.colorScheme.surface)
                .clickable(role = Role.Button, onClickLabel = stringResource(R.string.recurring_edit_action), onClick = onSelect)
                .semantics { customActions = listOf(CustomAccessibilityAction(stopLabel) { onStop(); true }) }
                .padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                modifier = Modifier.size(40.dp).background(categoryTint.copy(alpha = 0.14f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(categoryIconFor(row.category?.iconToken ?: ""), contentDescription = null, tint = categoryTint, modifier = Modifier.size(24.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(row.title, style = MaterialTheme.typography.titleMedium)
                    if (row.isDuplicate) {
                        Text(
                            stringResource(R.string.recurring_possible_duplicate),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onTertiaryContainer,
                            modifier = Modifier
                                .align(Alignment.CenterVertically)
                                .background(MaterialTheme.colorScheme.tertiaryContainer, RoundedCornerShape(50))
                                .padding(horizontal = 8.dp, vertical = 2.dp),
                        )
                    }
                }
                Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(formatSignedCurrency(rule.amount, rule.currencyCode), style = MaterialTheme.typography.titleMedium, color = amountColor)
        }
    }
}

private fun formatRuleDate(date: Instant, zoneId: ZoneId): String =
    DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(Locale.getDefault()).withZone(zoneId).format(date)

/** "Monthly", "Every 2 weeks", "Every 2 years" — iOS `RecurrenceFrequency.cadenceLabel(interval:)`. */
@Composable
fun cadenceLabel(frequency: RecurrenceFrequency, interval: Int): String = when (frequency) {
    RecurrenceFrequency.WEEKLY -> if (interval == 1) stringResource(R.string.cadence_weekly) else stringResource(R.string.cadence_weekly_n, interval)
    RecurrenceFrequency.MONTHLY -> if (interval == 1) stringResource(R.string.cadence_monthly) else stringResource(R.string.cadence_monthly_n, interval)
    RecurrenceFrequency.YEARLY -> if (interval == 1) stringResource(R.string.cadence_yearly) else stringResource(R.string.cadence_yearly_n, interval)
}
