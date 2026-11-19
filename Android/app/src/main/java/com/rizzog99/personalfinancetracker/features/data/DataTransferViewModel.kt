package com.rizzog99.personalfinancetracker.features.data

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RecurrenceRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.import.ImportCategoryPlanner
import com.rizzog99.personalfinancetracker.data.preferences.DismissedRecurrencePatternsRepository
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceDetector
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceSuggestion
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.combine

data class DataTransferUiState(val transactions: List<FinanceTransaction> = emptyList(), val categories: List<FinanceCategory> = emptyList())

class DataTransferViewModel(
    private val repository: TransactionRepository,
    private val categoryRepository: CategoryRepository,
    private val recurrenceRepository: RecurrenceRepository,
    private val dismissedPatterns: DismissedRecurrencePatternsRepository,
    private val clock: () -> Instant = Instant::now,
) : ViewModel() {
    val uiState: StateFlow<DataTransferUiState> = combine(repository.observeAll(), categoryRepository.observeAll(), ::DataTransferUiState)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DataTransferUiState())

    /** Imports [transactions], resolving each to its selected/created category. Reports the
     * resolved rows actually saved (with real category ids) on success, or null on failure —
     * the caller uses the resolved rows to detect recurring patterns for the next step. */
    fun import(transactions: List<FinanceTransaction>, categorySelections: Map<String, String?>, onFinished: (List<FinanceTransaction>?) -> Unit) = viewModelScope.launch {
        val result = runCatching {
            val known = uiState.value.categories.associateBy(FinanceCategory::id).toMutableMap()
            // One category per name the database would consider distinct, not one per CSV label.
            // Creating one each made a file containing both "Regali" and "🎁 Regali" abort on the
            // unique (normalizedName, type) index and fail the entire import. See ImportCategoryPlanner.
            val plan = ImportCategoryPlanner.plan(
                labels = categorySelections.filterValues { it == null }.keys,
                existing = known.values.toList(),
                typeOf = { label ->
                    if (transactions.any { it.categoryLabel == label && it.amount.signum() < 0 }) {
                        TransactionType.EXPENSE
                    } else {
                        TransactionType.INCOME
                    }
                },
            )
            val created = mutableMapOf<String, FinanceCategory>()
            plan.reuseExisting.forEach { (label, id) ->
                known[id]?.let { created[label] = it }
            }
            plan.create.forEach { planned ->
                val category = categoryRepository.add(
                    NewCategory(name = planned.name, iconToken = "tag", type = planned.type),
                ).also { known[it.id] = it }
                planned.labels.forEach { created[it] = category }
            }
            val resolved = transactions.map { transaction ->
                categorySelections[transaction.categoryLabel]?.let(known::get)?.let { category ->
                    transaction.copy(categoryId = category.id, categoryLabel = category.name)
                } ?: created[transaction.categoryLabel]?.let { category -> transaction.copy(categoryId = category.id, categoryLabel = category.name) } ?: transaction
            }
            repository.insertBatch(resolved)
            resolved
        }
        // The failure used to vanish here, leaving only "Couldn't import transactions" on screen and
        // nothing in the log to work from. Whatever else happens, the cause reaches logcat.
        result.exceptionOrNull()?.let { Log.e("DataTransferViewModel", "CSV import failed", it) }
        onFinished(result.getOrNull())
    }

    /**
     * Fixed expenses in the whole history, which now includes the rows just imported (#295): a
     * fixed expense shows up even when the file holds only one payment of it. Skips patterns that
     * already have a rule or were answered "Not fixed". Null on failure.
     */
    fun suggestRecurring(onResult: (List<RecurrenceSuggestion>?) -> Unit) = viewModelScope.launch {
        onResult(
            guarded("Recurring detection failed") {
                val today = clock()
                val transactions = repository.observeAll().first()
                val rules = recurrenceRepository.activeRules(today)
                val dismissed = dismissedPatterns.all()
                withContext(Dispatchers.Default) { RecurrenceDetector.detect(transactions, rules, dismissed, today) }
            },
        )
    }

    /**
     * "Plan N" / "Done": checked suggestions become forecast-only rules anchored on their latest
     * payment (auto-record is offered later, from Plan's card, #296); unchecked ones are
     * remembered as "Not fixed". iOS `persistSelectedRecurrenceRules`.
     */
    fun planRecurring(selected: List<RecurrenceSuggestion>, rejected: List<RecurrenceSuggestion>, onFinished: (Boolean) -> Unit) = viewModelScope.launch {
        // ponytail: one create per rule, like iOS; #314 makes the batch atomic.
        onFinished(
            guarded("Saving recurring rules failed") {
                selected.forEach { recurrenceRepository.create(it.toNewRule(autoRecord = false)) }
                dismissedPatterns.dismiss(rejected)
            } != null,
        )
    }

    /** Runs [block], logging a failure instead of letting it escape viewModelScope (#133); cancellation still propagates. */
    private suspend fun <T> guarded(message: String, block: suspend () -> T): T? = try {
        block()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        Log.e("DataTransferViewModel", message, failure)
        null
    }

    companion object {
        fun factory(
            repository: TransactionRepository,
            categoryRepository: CategoryRepository,
            recurrenceRepository: RecurrenceRepository,
            dismissedPatterns: DismissedRecurrencePatternsRepository,
        ) = viewModelFactory {
            initializer { DataTransferViewModel(repository, categoryRepository, recurrenceRepository, dismissedPatterns) }
        }
    }
}

