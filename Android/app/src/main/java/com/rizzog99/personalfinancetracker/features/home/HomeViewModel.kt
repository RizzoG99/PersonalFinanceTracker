package com.rizzog99.personalfinancetracker.features.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.dashboard.DashboardMetrics
import com.rizzog99.personalfinancetracker.domain.dashboard.DashboardMetricsCalculator
import com.rizzog99.personalfinancetracker.domain.dashboard.SafeToSpend
import com.rizzog99.personalfinancetracker.domain.dashboard.SafeToSpendCalculator
import com.rizzog99.personalfinancetracker.domain.paycycle.FinancialPeriod
import com.rizzog99.personalfinancetracker.domain.paycycle.PayCycleService
import com.rizzog99.personalfinancetracker.domain.pulse.FinancialPulseMetrics
import com.rizzog99.personalfinancetracker.domain.pulse.FinancialPulseCalculator
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update

data class HomeUiState(
    val isLoading: Boolean = true,
    /**
     * The read failed and retrying may fix it (#111 AC-01, #133). Distinct from an empty ledger:
     * `isError` means "we could not find out", not "there is nothing".
     */
    val isError: Boolean = false,
    val metrics: DashboardMetrics? = null,
    val period: FinancialPeriod? = null,
    val currencyCode: String = "EUR",
    val categories: List<FinanceCategory> = emptyList(),
    val pulseMetrics: FinancialPulseMetrics? = null,
    val dailyReminderEnabled: Boolean = false,
    val pulsePromptDismissed: Boolean = false,
    /** Home's hero (#298). */
    val safeToSpend: SafeToSpend? = null,
    val bufferPercent: Int = UserPreferencesRepository.DEFAULT_BUFFER_PERCENT,
    /** The day [safeToSpend] was worked out for: per-day figures count from it. */
    val today: LocalDate? = null,
    val hasTransactions: Boolean = false,
)

private data class HomePreferences(
    val payCycleStartDay: Int,
    val currencyCode: String,
    val bufferPercent: Int,
    val dailyReminderEnabled: Boolean,
    val pulsePromptDismissed: Boolean,
)

@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModel(
    transactionRepository: TransactionRepository,
    preferencesRepository: UserPreferencesRepository,
    categoryRepository: CategoryRepository,
    /** Active and past rules; Safe to Spend reserves what is still due. */
    recurrenceRules: Flow<List<RecurrenceRule>> = flowOf(emptyList()),
    private val clock: Clock = Clock.systemDefaultZone(),
    private val zoneId: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    /**
     * Bumped by [refresh] on resume, so a Home left open over midnight or across payday moves on
     * without waiting for a data change. Every recalculation reads the clock once, so a data change
     * after midnight is worked out for the new day too.
     */
    private val ticks = MutableStateFlow(0)

    private val preferences = combine(
        preferencesRepository.payCycleStartDay,
        preferencesRepository.baseCurrency,
        preferencesRepository.safeToSpendBufferPercent,
        preferencesRepository.dailyReminderEnabled,
        preferencesRepository.pulsePromptDismissed,
        ::HomePreferences,
    )

    // A preview of what is due, not the screen's point: a rules read failing just reserves nothing,
    // as iOS's `(try? await active) ?? []` (DashboardViewModel.swift at b649dff).
    private val rules = recurrenceRules.catch { emit(emptyList()) }

    private val dashboardState = combine(
        transactionRepository.observeAll(),
        rules,
        preferences,
        ticks,
    ) { transactions, rules, prefs, _ ->
        val now = Instant.now(clock)
        val today = now.atZone(zoneId).toLocalDate()
        val period = PayCycleService.financialMonthContaining(today, prefs.payCycleStartDay)
        HomeUiState(
            isLoading = false,
            metrics = DashboardMetricsCalculator.calculate(transactions, period, zoneId),
            period = period,
            currencyCode = prefs.currencyCode,
            pulseMetrics = FinancialPulseCalculator.calculate(transactions, now, zoneId),
            dailyReminderEnabled = prefs.dailyReminderEnabled,
            pulsePromptDismissed = prefs.pulsePromptDismissed,
            safeToSpend = SafeToSpendCalculator.compute(
                transactions, rules, prefs.payCycleStartDay, prefs.bufferPercent, prefs.currencyCode, now, zoneId,
            ),
            bufferPercent = prefs.bufferPercent,
            today = today,
            hasTransactions = transactions.isNotEmpty(),
        )
    }

    /**
     * Bumped by [retry]. `flatMapLatest` is what makes AC-05's concurrency clause structural rather
     * than a flag someone has to remember to check: a second activation cancels the first
     * subscription before opening the next, so two loads can never be in flight at once, however
     * fast the button is tapped.
     */
    private val retries = MutableStateFlow(0)

    val uiState: StateFlow<HomeUiState> = retries.flatMapLatest {
        combine(
            dashboardState,
            categoryRepository.observeAll(),
        ) { state, categories -> state.copy(categories = categories) }
            // Re-emitted on every activation so a retry visibly passes back through loading
            // instead of jumping from one error straight to the next.
            .onStart { emit(HomeUiState(isLoading = true)) }
            // Without this the failure escapes viewModelScope onto Android's default uncaught
            // handler and the process dies, leaving the spinner as the last thing the user saw
            // (#133). Frozen iOS catches the same failure in `DashboardViewModel.fetchAndCompute`.
            .catch { emit(HomeUiState(isLoading = false, isError = true)) }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HomeUiState())

    fun retry() {
        retries.update { it + 1 }
    }

    /** Re-reads the clock (on resume): a new day or a new cycle without any data change. */
    fun refresh() {
        ticks.update { it + 1 }
    }

    companion object {
        fun factory(
            transactionRepository: TransactionRepository,
            preferencesRepository: UserPreferencesRepository,
            categoryRepository: CategoryRepository,
            recurrenceRules: Flow<List<RecurrenceRule>>,
        ) = viewModelFactory {
            initializer { HomeViewModel(transactionRepository, preferencesRepository, categoryRepository, recurrenceRules) }
        }
    }
}
