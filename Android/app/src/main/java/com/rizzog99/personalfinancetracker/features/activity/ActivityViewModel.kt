package com.rizzog99.personalfinancetracker.features.activity

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionFilters
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionSearch
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionTypeFilter
import java.time.Clock
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
    val filterCategoryLabels: List<String> = emptyList(),
    val searchText: String = "",
    val filters: TransactionFilters = TransactionFilters(),
)

internal data class ActivityFilterSelection(
    val searchText: String = "",
    val filters: TransactionFilters = TransactionFilters(),
) {
    fun withSearchText(text: String) = copy(searchText = text)

    fun withType(type: TransactionTypeFilter) = copy(
        filters = filters.copy(
            type = type,
            category = if (type == filters.type) filters.category else null,
        ),
    )

    fun withFilters(filters: TransactionFilters) = copy(
        filters = if (filters.type == TransactionTypeFilter.ALL) filters.copy(category = null) else filters,
    )

    fun clearStructuredFilters() = copy(filters = TransactionFilters())

    fun clearSearchAndFilters() = ActivityFilterSelection()
}

internal fun availableActivityCategoryLabels(
    transactions: List<FinanceTransaction>,
    selection: ActivityFilterSelection,
    zoneId: ZoneId,
    clock: Clock = Clock.system(zoneId),
): List<String> {
    if (selection.filters.type == TransactionTypeFilter.ALL) return emptyList()

    val matchingTransactions = TransactionSearch.filter(
        transactions = transactions,
        searchText = selection.searchText,
        filters = selection.filters.copy(category = null),
        zoneId = zoneId,
        clock = clock,
    )
    return matchingTransactions
        .groupingBy(FinanceTransaction::categoryLabel)
        .eachCount()
        .entries
        .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenByDescending { it.key })
        .map { it.key }
}

class ActivityViewModel(
    private val transactionRepository: TransactionRepository,
    private val categoryRepository: CategoryRepository,
    private val recurrenceRepository: RecurrenceRepository,
    private val zoneId: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    private val transactions = MutableStateFlow<List<FinanceTransaction>>(emptyList())
    private val categories = MutableStateFlow<List<FinanceCategory>>(emptyList())
    private val filterSelection = MutableStateFlow(ActivityFilterSelection())

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    val uiState: StateFlow<ActivityUiState> = combine(
        transactions,
        categories,
        filterSelection,
    ) { allTransactions, allCategories, selection ->
        val filterCategoryLabels = availableActivityCategoryLabels(
            transactions = allTransactions,
            selection = selection,
            zoneId = zoneId,
        )
        val effectiveFilters = selection.filters.copy(
            category = selection.filters.category?.takeIf(filterCategoryLabels::contains),
        )
        ActivityUiState(
            allTransactions = allTransactions,
            visibleTransactions = TransactionSearch.filter(
                transactions = allTransactions,
                searchText = selection.searchText,
                filters = effectiveFilters,
                zoneId = zoneId,
            ),
            categories = allCategories,
            filterCategoryLabels = filterCategoryLabels,
            searchText = selection.searchText,
            filters = effectiveFilters,
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
        filterSelection.value = filterSelection.value.withSearchText(text)
    }

    fun updateTypeFilter(filter: TransactionTypeFilter) {
        filterSelection.value = filterSelection.value.withType(filter)
    }

    fun updateFilters(filters: TransactionFilters) {
        filterSelection.value = filterSelection.value.withFilters(filters)
    }

    fun clearFilters() {
        filterSelection.value = filterSelection.value.clearStructuredFilters()
    }

    fun clearSearchAndFilters() {
        filterSelection.value = filterSelection.value.clearSearchAndFilters()
    }

    suspend fun save(transaction: FinanceTransaction): Boolean = runCatching {
        transactionRepository.upsert(transaction)
    }.onFailure(::showError).isSuccess

    suspend fun createRecurringTransaction(rule: NewRecurrenceRule): Boolean = runCatching {
        recurrenceRepository.createAndMaterialize(rule)
    }.onFailure(::showError).isSuccess

    suspend fun updateThisAndFuture(transaction: FinanceTransaction): Boolean = runCatching {
        recurrenceRepository.updateThisAndFuture(transaction)
    }.onFailure(::showError).isSuccess

    suspend fun delete(transaction: FinanceTransaction): Boolean = runCatching {
        transactionRepository.delete(transaction.id)
    }.onFailure(::showError).isSuccess

    suspend fun deleteThisAndFuture(transaction: FinanceTransaction): Boolean = runCatching {
        transactionRepository.deleteThisAndFuture(requireNotNull(transaction.recurrenceRuleId), transaction.timestamp)
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
            recurrenceRepository: RecurrenceRepository,
        ) = viewModelFactory {
            initializer { ActivityViewModel(transactionRepository, categoryRepository, recurrenceRepository) }
        }
    }
}
