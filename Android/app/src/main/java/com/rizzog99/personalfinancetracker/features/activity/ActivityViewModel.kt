package com.rizzog99.personalfinancetracker.features.activity

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.R
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
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update

data class ActivityUiState(
    val isLoading: Boolean = true,
    /**
     * The ledger could not be read (#111 AC-02, #133).
     *
     * Kept separate from `allTransactions.isEmpty()` on purpose. Collapsed into one value, a failed
     * read renders as "Nothing here yet — add your first transaction", which invites someone whose
     * ledger is intact on disk to start a new one.
     */
    val isError: Boolean = false,
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

/** What the repositories answered, before any search or filter is applied. */
private data class ActivityLedger(
    val transactions: List<FinanceTransaction> = emptyList(),
    val categories: List<FinanceCategory> = emptyList(),
    val isLoading: Boolean = true,
    val isError: Boolean = false,
)

@OptIn(ExperimentalCoroutinesApi::class)
class ActivityViewModel(
    private val transactionRepository: TransactionRepository,
    private val categoryRepository: CategoryRepository,
    private val recurrenceRepository: RecurrenceRepository,
    private val zoneId: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    private val filterSelection = MutableStateFlow(ActivityFilterSelection())

    /** A string resource id, never text. See [showError]. */
    private val _error = MutableStateFlow<Int?>(null)
    val error: StateFlow<Int?> = _error

    /** See `HomeViewModel.retries` — same `flatMapLatest` guarantee (#111 AC-05). */
    private val retries = MutableStateFlow(0)

    /**
     * The ledger is read here rather than pushed into two `MutableStateFlow`s from `init`.
     *
     * The old shape collected both repository flows in `init` with no `catch`, so a read failure
     * escaped `viewModelScope` onto Android's uncaught handler — and the state it left behind was
     * an empty ledger, indistinguishable from a first run (#133).
     *
     * Kept deliberately separate from [filterSelection]: the user's search text and filters live in
     * their own flow, so moving through loading, error and back leaves them exactly as they were.
     */
    private val ledger: Flow<ActivityLedger> = retries.flatMapLatest {
        combine(
            transactionRepository.observeAll(),
            categoryRepository.observeAll(),
        ) { transactions, categories ->
            ActivityLedger(transactions = transactions, categories = categories, isLoading = false)
        }
            .onStart {
                // Best-effort: failing to seed defaults costs the starter categories, not the
                // ledger, so it reports itself and lets the read continue.
                runCatching { categoryRepository.seedDefaultsIfEmpty() }.onFailure { showError() }
                emit(ActivityLedger(isLoading = true))
            }
            .catch { emit(ActivityLedger(isLoading = false, isError = true)) }
    }

    val uiState: StateFlow<ActivityUiState> = combine(
        ledger,
        filterSelection,
    ) { ledger, selection ->
        val filterCategoryLabels = availableActivityCategoryLabels(
            transactions = ledger.transactions,
            selection = selection,
            zoneId = zoneId,
        )
        ActivityUiState(
            isLoading = ledger.isLoading,
            isError = ledger.isError,
            allTransactions = ledger.transactions,
            visibleTransactions = TransactionSearch.filter(
                transactions = ledger.transactions,
                searchText = selection.searchText,
                filters = selection.filters,
                zoneId = zoneId,
            ),
            categories = ledger.categories,
            filterCategoryLabels = filterCategoryLabels,
            searchText = selection.searchText,
            filters = selection.filters,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ActivityUiState())

    fun retry() {
        retries.update { it + 1 }
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
    }.onFailure { showError() }.isSuccess

    suspend fun createRecurringTransaction(rule: NewRecurrenceRule): Boolean = runCatching {
        recurrenceRepository.createAndMaterialize(rule)
    }.onFailure { showError() }.isSuccess

    suspend fun updateThisAndFuture(transaction: FinanceTransaction): Boolean = runCatching {
        recurrenceRepository.updateThisAndFuture(transaction)
    }.onFailure { showError() }.isSuccess

    suspend fun delete(transaction: FinanceTransaction): Boolean = runCatching {
        transactionRepository.delete(transaction.id)
    }.onFailure { showError() }.isSuccess

    suspend fun deleteThisAndFuture(transaction: FinanceTransaction): Boolean = runCatching {
        transactionRepository.deleteThisAndFuture(requireNotNull(transaction.recurrenceRuleId), transaction.timestamp)
    }.onFailure { showError() }.isSuccess

    fun clearError() {
        _error.value = null
    }

    /**
     * Publishes a string **resource id**, never the throwable's own text (#111 AC-04, #135).
     *
     * `Throwable.message` on a Room write failure is the SQLite driver's string: an exception class
     * name, an error code, the SQL, and the absolute path of the user's finance database — shown in
     * English whatever the device locale. Frozen iOS refuses the same thing for the same reason, in
     * `EditAddTransactionView`: "Not `error.localizedDescription`: a capture failure is a raw
     * AVFoundationErrorDomain code … that means nothing to a user reading it."
     *
     * ponytail: one string for every write path. They all mean the same thing to the person reading
     * it — the change did not stick and nothing was altered. Split it when a path needs a genuinely
     * different next action, not to mirror the exception taxonomy.
     */
    private fun showError() {
        _error.value = R.string.activity_update_failed
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
