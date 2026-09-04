package com.rizzog99.personalfinancetracker.features.activity

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionFilters
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionSearch
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionTypeFilter
import java.time.ZoneId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class ActivityUiState(
    val allTransactions: List<FinanceTransaction> = emptyList(),
    val visibleTransactions: List<FinanceTransaction> = emptyList(),
    val categories: List<FinanceCategory> = emptyList(),
    val searchText: String = "",
    val typeFilter: TransactionTypeFilter = TransactionTypeFilter.ALL,
)

class ActivityViewModel(
    private val transactionRepository: TransactionRepository,
    private val categoryRepository: CategoryRepository,
    private val zoneId: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    private val transactions = MutableStateFlow<List<FinanceTransaction>>(emptyList())
    private val categories = MutableStateFlow<List<FinanceCategory>>(emptyList())
    private val searchText = MutableStateFlow("")
    private val typeFilter = MutableStateFlow(TransactionTypeFilter.ALL)

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    val uiState: StateFlow<ActivityUiState> = combine(
        transactions,
        categories,
        searchText,
        typeFilter,
    ) { allTransactions, allCategories, query, type ->
        ActivityUiState(
            allTransactions = allTransactions,
            visibleTransactions = TransactionSearch.filter(
                transactions = allTransactions,
                searchText = query,
                filters = TransactionFilters(type = type),
                zoneId = zoneId,
            ),
            categories = allCategories,
            searchText = query,
            typeFilter = type,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ActivityUiState())

    init {
        viewModelScope.launch {
            runCatching { categoryRepository.seedDefaultsIfEmpty() }
                .onFailure(::showError)
            categoryRepository.observeAll().collect { categories.value = it }
        }
        viewModelScope.launch {
            transactionRepository.observeAll().collect { transactions.value = it }
        }
    }

    fun updateSearch(text: String) {
        searchText.value = text
    }

    fun updateTypeFilter(filter: TransactionTypeFilter) {
        typeFilter.value = filter
    }

    suspend fun save(transaction: FinanceTransaction): Boolean = runCatching {
        transactionRepository.upsert(transaction)
    }.onFailure(::showError).isSuccess

    suspend fun delete(transaction: FinanceTransaction): Boolean = runCatching {
        transactionRepository.delete(transaction.id)
    }.onFailure(::showError).isSuccess

    fun clearError() {
        _error.value = null
    }

    private fun showError(throwable: Throwable) {
        _error.value = throwable.message ?: "Unable to update transactions."
    }

    companion object {
        fun factory(
            transactionRepository: TransactionRepository,
            categoryRepository: CategoryRepository,
        ) = viewModelFactory {
            initializer { ActivityViewModel(transactionRepository, categoryRepository) }
        }
    }
}
