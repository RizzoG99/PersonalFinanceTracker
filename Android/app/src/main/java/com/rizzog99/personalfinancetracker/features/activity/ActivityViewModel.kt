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
import com.rizzog99.personalfinancetracker.domain.transaction.SearchDateRange
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionFilters
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionSearch
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionTypeFilter
import java.math.BigDecimal
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

internal data class ActivitySummaryTotals(
    val income: BigDecimal,
    val expenses: BigDecimal,
)

internal fun calculateActivitySummaryTotals(
    transactions: List<FinanceTransaction>,
): ActivitySummaryTotals = ActivitySummaryTotals(
    income = transactions
        .asSequence()
        .filter { it.amount > BigDecimal.ZERO }
        .fold(BigDecimal.ZERO) { total, transaction -> total + transaction.amount },
    expenses = transactions
        .asSequence()
        .filter { it.amount < BigDecimal.ZERO }
        .fold(BigDecimal.ZERO) { total, transaction -> total + transaction.amount.abs() },
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

internal data class ActivityAmountRangeValidation(
    val minimum: BigDecimal?,
    val maximum: BigDecimal?,
    val minimumHasError: Boolean,
    val maximumHasError: Boolean,
) {
    val isValid: Boolean
        get() = !minimumHasError && !maximumHasError
}

internal fun validateActivityAmountRange(
    minimumText: String,
    maximumText: String,
): ActivityAmountRangeValidation {
    fun String.amountOrNull(): BigDecimal? = replace(',', '.').toBigDecimalOrNull()

    val minimum = minimumText.amountOrNull()
    val maximum = maximumText.amountOrNull()
    val minimumIsMalformed = minimumText.isNotBlank() && minimum == null
    val maximumIsMalformed = maximumText.isNotBlank() && maximum == null
    val minimumIsNegative = minimum != null && minimum < BigDecimal.ZERO
    val maximumIsNegative = maximum != null && maximum < BigDecimal.ZERO
    val rangeIsReversed = minimum != null && maximum != null &&
        !minimumIsNegative && !maximumIsNegative && minimum > maximum

    return ActivityAmountRangeValidation(
        minimum = minimum,
        maximum = maximum,
        minimumHasError = minimumIsMalformed || minimumIsNegative || rangeIsReversed,
        maximumHasError = maximumIsMalformed || maximumIsNegative || rangeIsReversed,
    )
}

internal data class ActivityFilterDraft(
    val filters: TransactionFilters,
    val categoryLabels: List<String>,
    val categoryWasInvalidated: Boolean,
)

internal fun resolveActivityFilterDraft(
    transactions: List<FinanceTransaction>,
    searchText: String,
    appliedFilters: TransactionFilters,
    selectedCategory: String?,
    selectedDateRange: SearchDateRange?,
    amountRange: ActivityAmountRangeValidation,
    recurringOnly: Boolean,
    zoneId: ZoneId,
    clock: Clock = Clock.system(zoneId),
): ActivityFilterDraft? {
    if (!amountRange.isValid) return null

    val stagedFilters = appliedFilters.copy(
        category = null,
        dateRange = selectedDateRange,
        amountMin = amountRange.minimum,
        amountMax = amountRange.maximum,
        recurringOnly = recurringOnly,
    )
    val categoryLabels = availableActivityCategoryLabels(
        transactions = transactions,
        selection = ActivityFilterSelection(searchText = searchText, filters = stagedFilters),
        zoneId = zoneId,
        clock = clock,
    )
    val effectiveCategory = selectedCategory?.takeIf(categoryLabels::contains)
    return ActivityFilterDraft(
        filters = stagedFilters.copy(category = effectiveCategory),
        categoryLabels = categoryLabels,
        categoryWasInvalidated = selectedCategory != null && effectiveCategory == null,
    )
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
        ActivityUiState(
            allTransactions = allTransactions,
            visibleTransactions = TransactionSearch.filter(
                transactions = allTransactions,
                searchText = selection.searchText,
                filters = selection.filters,
                zoneId = zoneId,
            ),
            categories = allCategories,
            filterCategoryLabels = filterCategoryLabels,
            searchText = selection.searchText,
            filters = selection.filters,
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
