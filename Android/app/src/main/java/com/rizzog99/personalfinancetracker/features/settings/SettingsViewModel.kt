package com.rizzog99.personalfinancetracker.features.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class SettingsUiState(
    val payCycleStartDay: Int = 1,
)

class SettingsViewModel(
    private val preferencesRepository: UserPreferencesRepository,
) : ViewModel() {
    val uiState: StateFlow<SettingsUiState> = preferencesRepository.payCycleStartDay
        .combine(preferencesRepository.baseCurrency) { payCycleStartDay, _ ->
            SettingsUiState(payCycleStartDay = payCycleStartDay)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SettingsUiState())

    fun setPayCycleStartDay(day: Int) {
        viewModelScope.launch { preferencesRepository.setPayCycleStartDay(day) }
    }

    companion object {
        fun factory(preferencesRepository: UserPreferencesRepository): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T =
                    SettingsViewModel(preferencesRepository) as T
            }
    }
}
