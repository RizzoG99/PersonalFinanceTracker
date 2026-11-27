package com.rizzog99.personalfinancetracker.features.insights

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.GoalRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.goal.FinanceGoal
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerBreakdown
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerCalendar
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerGranularity
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerPeriod
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerType
import com.rizzog99.personalfinancetracker.domain.insights.canGoPrevious
import com.rizzog99.personalfinancetracker.domain.insights.HealthScore
import com.rizzog99.personalfinancetracker.domain.insights.computeHealthScore
import com.rizzog99.personalfinancetracker.domain.insights.snapshot
import com.rizzog99.personalfinancetracker.domain.insight.HealthScoreSnapshot
import com.rizzog99.personalfinancetracker.data.repository.InsightRepository
import com.rizzog99.personalfinancetracker.domain.paycycle.FinancialPeriod
import com.rizzog99.personalfinancetracker.domain.paycycle.PayCycleService
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.transaction.isGoalTransfer
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update

data class GoalProgress(val goal: FinanceGoal, val currentAmount: BigDecimal)
data class PaceInsight(val direction: PaceDirection, val percent: Int? = null)
enum class PaceDirection { UP, DOWN, FLAT, BUILDING }

data class InsightsUiState(
    val isLoading: Boolean = true,
    /** See [com.rizzog99.personalfinancetracker.features.home.HomeUiState.isError] (#111, #133). */
    val isError: Boolean = false,
    val period: FinancialPeriod? = null,
    val currencyCode: String = "EUR",
    val income: BigDecimal = BigDecimal.ZERO,
    val expenses: BigDecimal = BigDecimal.ZERO,
    val goals: List<GoalProgress> = emptyList(),
    val paceInsight: PaceInsight = PaceInsight(PaceDirection.BUILDING),
    /** iOS `FinancialHealthService` (#304); null without activity in the six-cycle window. */
    val health: HealthScore? = null,
    val ignoreSubscriptions: Boolean = false,
    val payCycleStartDay: Int = 1,
    /** Newest first, at most six: the detail's history chart (shown with two or more). */
    val snapshots: List<HealthScoreSnapshot> = emptyList(),
    /** The Breakdown explorer (#303): its selection, what it shows, and what its controls allow. */
    val explorerPeriod: ExplorerPeriod? = null,
    val explorerType: ExplorerType = ExplorerType.EXPENSES,
    val explorer: ExplorerBreakdown = ExplorerBreakdown.EMPTY,
    val canGoPrevious: Boolean = false,
    val canGoNext: Boolean = false,
    val firstTransaction: Instant? = null,
    val now: Instant = Instant.EPOCH,
    val zoneId: ZoneId = ZoneId.systemDefault(),
    /** Every transaction, for a row's drill-down, derived live so edits made from it show. */
    val transactions: List<FinanceTransaction> = emptyList(),
    val categories: List<FinanceCategory> = emptyList(),
)

private data class ExplorerSelection(val period: ExplorerPeriod, val type: ExplorerType)

@OptIn(ExperimentalCoroutinesApi::class)
class InsightsViewModel(
    private val transactionRepository: TransactionRepository,
    private val goalRepository: GoalRepository,
    private val preferencesRepository: UserPreferencesRepository,
    private val categoryRepository: CategoryRepository,
    private val clock: Clock = Clock.systemDefaultZone(),
    private val zoneId: ZoneId = ZoneId.systemDefault(),
    /** Health Score history; null where nothing should be recorded (Plan's goals-only use). */
    private val insightRepository: InsightRepository? = null,
) : ViewModel() {
    /** See `HomeViewModel.retries` — same `flatMapLatest` guarantee (#111 AC-05). */
    private val retries = MutableStateFlow(0)

    /** Read per use: a locale change can move the first weekday while this model lives on. */
    private val calendar get() = ExplorerCalendar.of(zoneId)

    /**
     * Set once here and only by the user: data, pay-cycle and foreground refreshes never reset it,
     * so an edit from a drill-down doesn't throw the user back to this month (iOS `InsightsViewModel.swift:12-17`).
     */
    private val selection = MutableStateFlow(
        ExplorerSelection(ExplorerPeriod.current(ExplorerGranularity.MONTH, clock.instant(), calendar), ExplorerType.EXPENSES),
    )

    /** Re-reads "now" (iOS reloads the explorer on every foreground): a new day or month re-enables ›, moves Δ's cutoff. */
    private val nowTicks = MutableStateFlow(0)
    fun refreshNow() = nowTicks.update { it + 1 }

    /** Bumped after a snapshot is saved, so the history re-reads. */
    private val snapshotTicks = MutableStateFlow(0)
    private val snapshots: Flow<List<HealthScoreSnapshot>> = snapshotTicks.mapLatest {
        // History is decoration: a failed read shows none rather than turning Insights into an error.
        insightRepository?.let { repo -> runCatching { repo.recentSnapshots(6) }.getOrElse { error -> rethrowIfCancelled(error); emptyList() } }.orEmpty()
    }

    /** iOS keeps this in UserDefaults and reloads on change; here the stored preference drives the score. */
    fun setIgnoreSubscriptions(ignore: Boolean) {
        viewModelScope.launch { runCatching { preferencesRepository.setHealthScoreIgnoreSubscriptions(ignore) } }
    }

    fun selectType(type: ExplorerType) = selection.update { it.copy(type = type) }
    fun previousPeriod() = selection.update { it.copy(period = it.period.previous(calendar)) }
    fun nextPeriod() = selection.update { it.copy(period = it.period.next(calendar)) }
    fun selectGranularity(granularity: ExplorerGranularity) =
        selection.update { it.copy(period = it.period.withGranularity(granularity, calendar)) }
    fun selectCustomRange(from: LocalDate, through: LocalDate) =
        selection.update { it.copy(period = ExplorerPeriod.custom(from, through, calendar)) }

    val uiState: StateFlow<InsightsUiState> = retries.flatMapLatest { insights() }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), InsightsUiState())

    fun retry() {
        retries.update { it + 1 }
    }

    private fun insights(): Flow<InsightsUiState> = combine(
        transactionRepository.observeAll(),
        goalRepository.observeAll(),
        combine(
            preferencesRepository.payCycleStartDay,
            preferencesRepository.baseCurrency,
            preferencesRepository.healthScoreIgnoreSubscriptions,
        ) { day, currency, ignore -> Triple(day, currency, ignore) },
        categoryRepository.observeAll(),
    ) { transactions, goals, (payCycleStartDay, currencyCode, ignoreSubscriptions), categories ->
        val period = PayCycleService.currentFinancialMonth(payCycleStartDay, clock)
        val periodTransactions = transactions.filter { it.timestamp.atZone(zoneId).toLocalDate() in period }
        val expenseTransactions = transactions.filter { it.amount < BigDecimal.ZERO && !it.isGoalTransfer }
        val previousPeriod = PayCycleService.financialMonthContaining(period.start.minusDays(1), payCycleStartDay)
        val currentSpend = expenseTransactions.inPeriod(period, zoneId)
        val previousSpend = expenseTransactions.inPeriod(previousPeriod, zoneId)
        InsightsUiState(
            isLoading = false,
            period = period,
            currencyCode = currencyCode,
            income = periodTransactions.filter { it.amount > BigDecimal.ZERO }
                .fold(BigDecimal.ZERO) { total, transaction -> total + transaction.amount },
            expenses = periodTransactions.filter { it.amount < BigDecimal.ZERO }
                .fold(BigDecimal.ZERO) { total, transaction -> total + transaction.amount.abs() },
            goals = goals.map { goal ->
                GoalProgress(
                    goal = goal,
                    currentAmount = transactions.asSequence()
                        .filter { it.goalId == goal.id }
                        .fold(BigDecimal.ZERO) { total, transaction -> total + transaction.amount.abs() },
                )
            },
            paceInsight = paceInsight(currentSpend, previousSpend),
            ignoreSubscriptions = ignoreSubscriptions,
            payCycleStartDay = payCycleStartDay,
            firstTransaction = transactions.minOfOrNull { it.timestamp },
            zoneId = zoneId,
            transactions = transactions,
            categories = categories,
        )
    }.combine(combine(selection, nowTicks, snapshots) { selection, _, history -> selection to history }) { state, (selection, history) ->
        // Inside the same flow as the reads, so a failure here lands in the error state below (#133).
        // One "now" for the explorer, the score and its snapshot, re-read on every foreground.
        val now = clock.instant()
        val calendar = calendar
        state.copy(
            health = computeHealthScore(
                state.transactions, state.categories, state.payCycleStartDay, state.ignoreSubscriptions,
                now.atZone(zoneId).toLocalDate(), zoneId,
            ),
            snapshots = history,
            explorerPeriod = selection.period,
            explorerType = selection.type,
            explorer = ExplorerBreakdown.build(state.transactions, state.categories, selection.period, selection.type, now, calendar),
            canGoPrevious = canGoPrevious(selection.period, state.firstTransaction, calendar),
            canGoNext = !selection.period.isCurrent(now),
            now = now,
        )
    }
        .onEach { state -> recordSnapshot(state) }
        .onStart { emit(InsightsUiState(isLoading = true)) }
        .catch { emit(InsightsUiState(isLoading = false, isError = true)) }

    /**
     * The day's reading (iOS `saveSnapshotIfNeeded`): only from a loaded, error-free state, once per
     * local day across every model (the repository serializes), then the history re-reads. A failed
     * write is dropped: it must neither break Insights nor touch the rows already saved.
     */
    private suspend fun recordSnapshot(state: InsightsUiState) {
        val repo = insightRepository ?: return
        val health = state.health ?: return
        if (state.isLoading || state.isError) return
        val today = state.now.atZone(zoneId).toLocalDate()
        runCatching { repo.saveSnapshotIfNeeded(health.snapshot(state.now), zoneId) }
            .onSuccess { saved ->
                // Re-read after we saved, and once a day after another model did (Insights, Plan and
                // the wide page each hold one): a skipped save mustn't leave this history stale.
                // ponytail: once per day per model, so a re-read can never loop back into itself.
                if (saved || historyCheckedOn != today) {
                    historyCheckedOn = today
                    snapshotTicks.update { it + 1 }
                }
            }
            .onFailure(::rethrowIfCancelled)
    }

    private var historyCheckedOn: java.time.LocalDate? = null

    companion object {
        fun factory(
            transactionRepository: TransactionRepository,
            goalRepository: GoalRepository,
            preferencesRepository: UserPreferencesRepository,
            categoryRepository: CategoryRepository,
            clock: Clock = Clock.systemDefaultZone(),
            insightRepository: InsightRepository? = null,
        ) = viewModelFactory {
            initializer {
                InsightsViewModel(transactionRepository, goalRepository, preferencesRepository, categoryRepository, clock, clock.zone, insightRepository)
            }
        }
    }

    fun addGoal(goal: NewGoal, onFinished: (Boolean) -> Unit) = viewModelScope.launch {
        onFinished(runCatching { goalRepository.add(goal) }.isSuccess)
    }

    fun updateGoal(goal: FinanceGoal, onFinished: (Boolean) -> Unit) = viewModelScope.launch {
        onFinished(runCatching { goalRepository.update(goal) }.isSuccess)
    }

    fun deleteGoal(goal: FinanceGoal, onFinished: (Boolean) -> Unit) = viewModelScope.launch {
        onFinished(runCatching { goalRepository.delete(goal.id) }.isSuccess)
    }

    fun addFunds(goal: FinanceGoal, amount: BigDecimal, currencyCode: String, onFinished: (Boolean) -> Unit) = viewModelScope.launch {
        val result = runCatching {
            require(amount > BigDecimal.ZERO) { "A contribution must be greater than zero." }
            transactionRepository.upsert(
                FinanceTransaction(
                    id = UUID.randomUUID().toString(),
                    timestamp = Instant.now(),
                    amount = amount.negate(),
                    note = "",
                    categoryLabel = "→ ${goal.name}",
                    categoryId = null,
                    currencyCode = currencyCode,
                    goalId = goal.id,
                    recurrenceRuleId = null,
                ),
            )
        }
        onFinished(result.isSuccess)
    }
}

private fun List<FinanceTransaction>.inPeriod(period: FinancialPeriod, zoneId: ZoneId) =
    asSequence().filter { it.timestamp.atZone(zoneId).toLocalDate() in period }
        .fold(BigDecimal.ZERO) { total, transaction -> total + transaction.amount.abs() }

private fun paceInsight(current: BigDecimal, previous: BigDecimal): PaceInsight {
    if (previous <= BigDecimal.ZERO) return PaceInsight(PaceDirection.BUILDING)
    val percent = current.subtract(previous).abs().multiply(BigDecimal(100)).divide(previous, 0, java.math.RoundingMode.DOWN).toInt()
    return when {
        current < previous.multiply(BigDecimal("0.95")) -> PaceInsight(PaceDirection.DOWN, percent)
        current > previous.multiply(BigDecimal("1.10")) -> PaceInsight(PaceDirection.UP, percent)
        else -> PaceInsight(PaceDirection.FLAT)
    }
}

/** `runCatching` must not swallow cancellation: a cancelled collector stays cancelled (#133). */
private fun rethrowIfCancelled(error: Throwable) {
    if (error is kotlinx.coroutines.CancellationException) throw error
}
