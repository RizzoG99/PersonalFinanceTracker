package com.rizzog99.personalfinancetracker.features.plan

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RecurrenceRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.recurrence.UpcomingCharge
import com.rizzog99.personalfinancetracker.domain.recurrence.UpcomingTotals
import com.rizzog99.personalfinancetracker.domain.recurrence.hasActiveRules
import com.rizzog99.personalfinancetracker.domain.recurrence.title
import com.rizzog99.personalfinancetracker.domain.recurrence.upcomingCharges
import com.rizzog99.personalfinancetracker.domain.recurrence.upcomingTotals
import com.rizzog99.personalfinancetracker.features.insights.GoalSheetsHost
import com.rizzog99.personalfinancetracker.features.insights.GoalsBlock
import com.rizzog99.personalfinancetracker.features.insights.InsightsViewModel
import com.rizzog99.personalfinancetracker.features.insights.rememberGoalSheets
import com.rizzog99.personalfinancetracker.ui.components.ErrorState
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.components.LoadingState
import com.rizzog99.personalfinancetracker.ui.components.MainTopBar
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import java.math.BigDecimal
import java.time.Clock
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update

/** Shared with tests (`NavShellMarkers.PLAN_CONTENT_TAG`): present in every loaded Plan state. */
const val PLAN_CONTENT_TAG = "plan-content"

data class PlanUiState(
    val isLoading: Boolean = true,
    val isError: Boolean = false,
    val hasActiveRules: Boolean = false,
    val upcoming: List<UpcomingCharge> = emptyList(),
    val totals: UpcomingTotals = UpcomingTotals(BigDecimal.ZERO, BigDecimal.ZERO),
    val baseCurrency: String = "EUR",
    /** Expense categories with a monthly limit (D-01: limits only until #306 adds cycle progress). */
    val budgets: List<FinanceCategory> = emptyList(),
)

@OptIn(ExperimentalCoroutinesApi::class)
class PlanViewModel(
    private val recurrenceRepository: RecurrenceRepository,
    private val categoryRepository: CategoryRepository,
    private val preferencesRepository: UserPreferencesRepository,
    private val clock: Clock = Clock.systemDefaultZone(),
) : ViewModel() {
    private val retries = MutableStateFlow(0)

    val uiState: StateFlow<PlanUiState> = retries.flatMapLatest {
        combine(
            recurrenceRepository.observeAll(),
            categoryRepository.observeAll(),
            preferencesRepository.baseCurrency,
        ) { rules, categories, baseCurrency ->
            val now = clock.instant()
            val upcoming = upcomingCharges(rules, now, clock.zone)
            PlanUiState(
                isLoading = false,
                hasActiveRules = hasActiveRules(rules, now, clock.zone),
                upcoming = upcoming,
                totals = upcomingTotals(upcoming, baseCurrency),
                baseCurrency = baseCurrency,
                budgets = categories
                    .filter { it.type == TransactionType.EXPENSE && (it.monthlyBudget ?: BigDecimal.ZERO) > BigDecimal.ZERO }
                    .sortedBy { it.name },
            )
        }
            .onStart { emit(PlanUiState()) }
            .catch { emit(PlanUiState(isLoading = false, isError = true)) }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlanUiState())

    fun retry() = retries.update { it + 1 }

    companion object {
        fun factory(application: PersonalFinanceApplication) = viewModelFactory {
            initializer {
                PlanViewModel(application.recurrenceRepository, application.categoryRepository, application.preferencesRepository)
            }
        }
    }
}

@Composable
private fun insightsViewModel(): InsightsViewModel {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    // ponytail: goals and their actions still live on InsightsViewModel (D-06); split it out once #291's
    // factory change has landed, if Insights' extra work here ever shows up in a profile.
    return viewModel(
        factory = InsightsViewModel.factory(
            application.transactionRepository,
            application.goalRepository,
            application.preferencesRepository,
        ),
    )
}

/**
 * The Plan tab (#283, iOS `PlanView.swift` at b649dff): what's coming and what I want — upcoming
 * recurring payments, budgets and goals on one page, or one welcome state when all three are empty.
 */
@Composable
fun PlanScreen(
    isDarkTheme: Boolean,
    onToggleTheme: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenRecurring: () -> Unit,
    onEditRule: (String) -> Unit,
    onAddRule: () -> Unit,
    onOpenBudgets: () -> Unit,
) {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val viewModel: PlanViewModel = viewModel(factory = PlanViewModel.factory(application))
    val goalsViewModel = insightsViewModel()
    val state by viewModel.uiState.collectAsState()
    val goalsState by goalsViewModel.uiState.collectAsState()
    val sheets = rememberGoalSheets()
    val snackbarHostState = remember { SnackbarHostState() }

    Scaffold(
        topBar = {
            MainTopBar(
                title = stringResource(R.string.tab_plan),
                isDarkTheme = isDarkTheme,
                onToggleTheme = onToggleTheme,
                onOpenSettings = onOpenSettings,
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) { padding ->
        val modifier = Modifier.padding(padding).fillMaxSize()
        when {
            // Both loads first, so a store with data never flashes the welcome state (`PlanView.swift:25-27`).
            state.isLoading || goalsState.isLoading -> LoadingState(modifier = modifier)
            state.isError || goalsState.isError -> ErrorState(
                message = stringResource(R.string.error_state_message),
                onRetry = {
                    viewModel.retry()
                    goalsViewModel.retry()
                },
                modifier = modifier,
            )
            else -> Column(
                modifier = modifier
                    .testTag(PLAN_CONTENT_TAG)
                    .verticalScroll(rememberScrollState())
                    .padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 112.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                if (!state.hasActiveRules && state.budgets.isEmpty() && goalsState.goals.isEmpty()) {
                    PlanWelcome(
                        onAddRule = onAddRule,
                        onCreateBudget = onOpenBudgets,
                        onAddGoal = { sheets.creating = true },
                    )
                } else {
                    ComingUpSection(state, onOpenRecurring, onEditRule, onAddRule)
                    BudgetsSection(state.budgets, onOpenBudgets)
                    GoalsBlock(goalsState, sheets)
                }
            }
        }
    }
    GoalSheetsHost(sheets, goalsState, goalsViewModel, snackbarHostState)
}

/** The wide layout's Goals destination (iPad `IPadGoalsView`): Plan's goals block on its own. */
@Composable
fun GoalsScreen(isDarkTheme: Boolean, onToggleTheme: () -> Unit, onOpenSettings: () -> Unit) {
    val goalsViewModel = insightsViewModel()
    val goalsState by goalsViewModel.uiState.collectAsState()
    val sheets = rememberGoalSheets()
    val snackbarHostState = remember { SnackbarHostState() }
    Scaffold(
        topBar = {
            MainTopBar(
                title = stringResource(R.string.goals_title),
                isDarkTheme = isDarkTheme,
                onToggleTheme = onToggleTheme,
                onOpenSettings = onOpenSettings,
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) { padding ->
        val modifier = Modifier.padding(padding).fillMaxSize()
        when {
            goalsState.isLoading -> LoadingState(modifier = modifier)
            goalsState.isError -> ErrorState(stringResource(R.string.error_state_message), goalsViewModel::retry, modifier)
            else -> Column(modifier.verticalScroll(rememberScrollState()).padding(16.dp)) { GoalsBlock(goalsState, sheets) }
        }
    }
    GoalSheetsHost(sheets, goalsState, goalsViewModel, snackbarHostState)
}

@Composable
private fun SectionHeader(title: String, subtitle: String, action: (@Composable () -> Unit)? = null) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
            Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
        }
        action?.invoke()
    }
}

/** One line and its add action, for a section with nothing in it (`PlanView.swift:167-174`). */
@Composable
private fun SectionEmpty(title: String, message: String, actionLabel: String, onAction: () -> Unit) {
    FinanceCard {
        Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedButton(onClick = onAction) { Text(actionLabel) }
        }
    }
}

@Composable
private fun ComingUpSection(
    state: PlanUiState,
    onOpenRecurring: () -> Unit,
    onEditRule: (String) -> Unit,
    onAddRule: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader(stringResource(R.string.plan_coming_up), stringResource(R.string.plan_next_14_days)) {
            TextButton(onClick = onOpenRecurring, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(stringResource(R.string.plan_see_all), fontWeight = FontWeight.Bold)
            }
        }
        when {
            !state.hasActiveRules -> SectionEmpty(
                stringResource(R.string.plan_no_recurring),
                stringResource(R.string.plan_no_recurring_detail),
                stringResource(R.string.plan_add_recurring),
                onAddRule,
            )
            state.upcoming.isEmpty() -> FinanceCard {
                Text(
                    stringResource(R.string.plan_nothing_due),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().padding(20.dp),
                )
            }
            else -> {
                Text(
                    stringResource(
                        R.string.plan_in_out,
                        formatCurrency(state.totals.inflow, state.baseCurrency),
                        formatCurrency(state.totals.outflow, state.baseCurrency),
                    ),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                FinanceCard {
                    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                        val zone = ZoneId.systemDefault()
                        val days = state.upcoming.groupBy { it.date.atZone(zone).toLocalDate() }.toList()
                        days.forEachIndexed { index, (day, charges) ->
                            Text(
                                dayLabel(day),
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp).semantics { heading() },
                            )
                            charges.forEach { charge -> UpcomingRow(charge) { onEditRule(charge.rule.id) } }
                            if (index != days.lastIndex) HorizontalDivider()
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun dayLabel(day: LocalDate): String {
    val locale = LocalConfiguration.current.locales[0]
    val formatted = day.format(DateTimeFormatter.ofPattern("EEE d MMM", locale))
    // Day-based, not relative hours (`UpcomingChargeRow.swift:33-41`).
    return when (ChronoUnit.DAYS.between(LocalDate.now(), day)) {
        0L -> stringResource(R.string.plan_today_day, formatted)
        1L -> stringResource(R.string.plan_tomorrow_day, formatted)
        else -> formatted
    }
}

@Composable
private fun UpcomingRow(charge: UpcomingCharge, onClick: () -> Unit) {
    val hint = stringResource(R.string.plan_edits_rule)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            // The row is about the commitment: it opens the rule, not one occurrence (`PlanView.swift:196-202`).
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { onClick(label = hint) { onClick(); true } }
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(charge.rule.title(), modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Text(
            formatCurrency(charge.rule.amount, charge.rule.currencyCode),
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun BudgetsSection(budgets: List<FinanceCategory>, onOpenBudgets: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader(stringResource(R.string.budgets_title), stringResource(R.string.plan_budgets_subtitle)) {
            TextButton(onClick = onOpenBudgets, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(stringResource(R.string.plan_manage), fontWeight = FontWeight.Bold)
            }
        }
        if (budgets.isEmpty()) {
            SectionEmpty(
                stringResource(R.string.plan_no_budgets),
                stringResource(R.string.plan_no_budgets_detail),
                stringResource(R.string.plan_create_budget),
                onOpenBudgets,
            )
        } else {
            FinanceCard {
                Column(modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                    budgets.forEach { category ->
                        Row(
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 8.dp)
                                .semantics(mergeDescendants = true) {},
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Text(category.name, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                            Text(
                                stringResource(R.string.plan_budget_limit, formatCurrency(category.monthlyBudget ?: BigDecimal.ZERO, category.currencyCode)),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.End,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PlanWelcome(onAddRule: () -> Unit, onCreateBudget: () -> Unit, onAddGoal: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            stringResource(R.string.plan_welcome_title),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            stringResource(R.string.plan_welcome_message),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Button(onClick = onAddRule) { Text(stringResource(R.string.plan_add_recurring)) }
        TextButton(onClick = onCreateBudget) { Text(stringResource(R.string.plan_create_budget)) }
        TextButton(onClick = onAddGoal) { Text(stringResource(R.string.add_goal)) }
    }
}
