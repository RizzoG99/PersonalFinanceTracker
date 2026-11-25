package com.rizzog99.personalfinancetracker.features.travels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.data.repository.TravelRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.travel.FinanceTravel
import com.rizzog99.personalfinancetracker.domain.travel.TravelSummary
import com.rizzog99.personalfinancetracker.domain.travel.travelSummaries
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
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
import kotlinx.coroutines.withContext

data class TravelsUiState(
    val isLoading: Boolean = true,
    val isError: Boolean = false,
    val travels: List<FinanceTravel> = emptyList(),
    /** Every travel with its totals, empty ones included, newest first (iOS `TravelsView.summaries`). */
    val summaries: List<TravelSummary> = emptyList(),
    val transactions: List<FinanceTransaction> = emptyList(),
    val categories: List<FinanceCategory> = emptyList(),
) {
    /** A travel's members, newest first (iOS `members(of:)`). */
    fun members(travelId: String): List<FinanceTransaction> =
        transactions.filter { it.travelId == travelId }.sortedByDescending { it.timestamp }
}

/**
 * The Travels page and a travel's detail page (#284). Same read and error shape as
 * `ActivityViewModel`: a failed read is a retryable error state, never an empty list (#133), and a
 * failed write reports a string resource id, never the throwable's text (#135).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TravelsViewModel(
    private val transactionRepository: TransactionRepository,
    private val travelRepository: TravelRepository,
    private val categoryRepository: CategoryRepository,
    private val zoneId: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    private val retries = MutableStateFlow(0)
    private val _error = MutableStateFlow<Int?>(null)
    val error: StateFlow<Int?> = _error

    val uiState: StateFlow<TravelsUiState> = retries.flatMapLatest {
        combine(
            transactionRepository.observeAll(),
            travelRepository.observeAll(),
            categoryRepository.observeAll(),
        ) { transactions, travels, categories ->
            TravelsUiState(
                isLoading = false,
                travels = travels,
                summaries = travelSummaries(transactions, travels, zoneId),
                transactions = transactions,
                categories = categories,
            )
        }
            .onStart { emit(TravelsUiState(isLoading = true)) }
            .catch { emit(TravelsUiState(isLoading = false, isError = true)) }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), TravelsUiState())

    fun retry() = retries.update { it + 1 }

    fun clearError() {
        _error.value = null
    }

    suspend fun add(name: String, symbolName: String): String? {
        var id: String? = null
        write { id = travelRepository.add(name, symbolName).id }
        return id
    }

    suspend fun rename(id: String, name: String, symbolName: String) = write { travelRepository.update(id, name, symbolName) }

    suspend fun delete(id: String) = write { travelRepository.delete(id) }

    suspend fun removeFromTravel(transaction: FinanceTransaction) = write { travelRepository.assign(listOf(transaction.id), null) }

    /** A member edited from the detail page: a plain save of that one row. */
    suspend fun save(transaction: FinanceTransaction) = write { transactionRepository.upsert(transaction) }

    private suspend fun write(block: suspend () -> Unit): Boolean = withContext(Dispatchers.Main.immediate) {
        runCatching { block() }.onFailure { _error.value = R.string.activity_update_failed }.isSuccess
    }

    companion object {
        fun factory(
            transactionRepository: TransactionRepository,
            travelRepository: TravelRepository,
            categoryRepository: CategoryRepository,
        ) = viewModelFactory {
            initializer { TravelsViewModel(transactionRepository, travelRepository, categoryRepository) }
        }
    }
}
