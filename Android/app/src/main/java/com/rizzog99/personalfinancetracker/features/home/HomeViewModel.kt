package com.rizzog99.personalfinancetracker.features.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.domain.dashboard.DashboardMetrics
import com.rizzog99.personalfinancetracker.domain.dashboard.DashboardMetricsCalculator
import com.rizzog99.personalfinancetracker.domain.paycycle.FinancialPeriod
import com.rizzog99.personalfinancetracker.domain.paycycle.PayCycleService
import java.time.Clock
import java.time.ZoneId
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

data class HomeUiState(
    val isLoading: Boolean = true,
    val metrics: DashboardMetrics? = null,
    val period: FinancialPeriod? = null,
    val currencyCode: String = "EUR",
)

class HomeViewModel(
    transactionRepository: TransactionRepository,
    preferencesRepository: UserPreferencesRepository,
    private val clock: Clock = Clock.systemDefaultZone(),
    private val zoneId: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    val uiState: StateFlow<HomeUiState> = combine(
        transactionRepository.observeAll(),
        preferencesRepository.payCycleStartDay,
        preferencesRepository.baseCurrency,
    ) { transactions, payCycleStartDay, currencyCode ->
        val period = PayCycleService.currentFinancialMonth(payCycleStartDay, clock)
        HomeUiState(
            isLoading = false,
            metrics = DashboardMetricsCalculator.calculate(transactions, period, zoneId),
            period = period,
            currencyCode = currencyCode,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HomeUiState())

    companion object {
        fun factory(
            transactionRepository: TransactionRepository,
            preferencesRepository: UserPreferencesRepository,
        ) = viewModelFactory {
            initializer { HomeViewModel(transactionRepository, preferencesRepository) }
        }
    }
}
