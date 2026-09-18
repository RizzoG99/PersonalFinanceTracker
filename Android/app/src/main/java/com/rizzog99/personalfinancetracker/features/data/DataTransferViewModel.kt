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
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
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

    fun addRecurrenceRules(rules: List<NewRecurrenceRule>, onFinished: (Boolean) -> Unit) = viewModelScope.launch {
        onFinished(runCatching { rules.forEach { recurrenceRepository.create(it) } }.isSuccess)
    }

    companion object {
        fun factory(repository: TransactionRepository, categoryRepository: CategoryRepository, recurrenceRepository: RecurrenceRepository) = viewModelFactory {
            initializer { DataTransferViewModel(repository, categoryRepository, recurrenceRepository) }
        }
    }
}

