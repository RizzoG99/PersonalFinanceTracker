package com.rizzog99.personalfinancetracker.features.settings

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import kotlin.coroutines.cancellation.CancellationException
import androidx.lifecycle.viewModelScope
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class SettingsUiState(
    val payCycleStartDay: Int = 1,
    val bufferPercent: Int = UserPreferencesRepository.DEFAULT_BUFFER_PERCENT,
)

class SettingsViewModel(
    private val preferencesRepository: UserPreferencesRepository,
) : ViewModel() {
    val uiState: StateFlow<SettingsUiState> = preferencesRepository.payCycleStartDay
        .combine(preferencesRepository.safeToSpendBufferPercent) { payCycleStartDay, bufferPercent ->
            SettingsUiState(payCycleStartDay = payCycleStartDay, bufferPercent = bufferPercent)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SettingsUiState())

    fun setPayCycleStartDay(day: Int) = write { preferencesRepository.setPayCycleStartDay(day) }

    fun setBufferPercent(percent: Int) = write { preferencesRepository.setSafeToSpendBufferPercent(percent) }

    /**
     * A failed DataStore write must not escape `viewModelScope` and kill the process (#133). The
     * screen keeps showing the stored value, which is the honest state; the cause goes to the log
     * only (#135).
     */
    private fun write(block: suspend () -> Unit) {
        viewModelScope.launch {
            try {
                block()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                Log.e("SettingsViewModel", "Preference write failed", failure)
            }
        }
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
