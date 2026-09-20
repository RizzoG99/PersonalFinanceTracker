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
import com.rizzog99.personalfinancetracker.domain.paycycle.FinancialPeriod
import com.rizzog99.personalfinancetracker.domain.paycycle.PayCycleService
import com.rizzog99.personalfinancetracker.domain.pulse.FinancialPulseMetrics
import com.rizzog99.personalfinancetracker.domain.pulse.FinancialPulseCalculator
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
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
)

@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModel(
    transactionRepository: TransactionRepository,
    preferencesRepository: UserPreferencesRepository,
    categoryRepository: CategoryRepository,
    private val clock: Clock = Clock.systemDefaultZone(),
    private val zoneId: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    // combine() only has typed overloads up to 5 flows; nest the category flow rather than
    // widen every arg to Array<Any?> for one extra source.
    private val dashboardState = combine(
        transactionRepository.observeAll(),
        preferencesRepository.payCycleStartDay,
        preferencesRepository.baseCurrency,
        preferencesRepository.dailyReminderEnabled,
        preferencesRepository.pulsePromptDismissed,
    ) { transactions, payCycleStartDay, currencyCode, dailyReminderEnabled, pulsePromptDismissed ->
        val period = PayCycleService.currentFinancialMonth(payCycleStartDay, clock)
        val now = Instant.now(clock)
        val pulseMetrics = FinancialPulseCalculator.calculate(transactions, now, zoneId)
        HomeUiState(
            isLoading = false,
            metrics = DashboardMetricsCalculator.calculate(transactions, period, zoneId),
            period = period,
            currencyCode = currencyCode,
            pulseMetrics = pulseMetrics,
            dailyReminderEnabled = dailyReminderEnabled,
            pulsePromptDismissed = pulsePromptDismissed,
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

    companion object {
        fun factory(
            transactionRepository: TransactionRepository,
            preferencesRepository: UserPreferencesRepository,
            categoryRepository: CategoryRepository,
        ) = viewModelFactory {
            initializer { HomeViewModel(transactionRepository, preferencesRepository, categoryRepository) }
        }
    }
}
