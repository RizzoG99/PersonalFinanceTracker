package com.rizzog99.personalfinancetracker.features.recurring

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class RecurringRuleRow(
    val rule: RecurrenceRule,
    val title: String,
    val nextDate: Instant?,
    val isDuplicate: Boolean,
    val category: FinanceCategory?,
)

data class RecurringRulesUiState(
    val isLoading: Boolean = true,
    val rows: List<RecurringRuleRow> = emptyList(),
    val monthlySpend: BigDecimal = BigDecimal.ZERO,
    val categories: List<FinanceCategory> = emptyList(),
) {
    val activeCount: Int get() = rows.size
}

// #294 red baseline (D-08): typed no-op stubs.
class RecurringRulesViewModel(
    private val recurrenceRepository: RecurrenceRepository,
    private val transactionRepository: TransactionRepository,
    private val categoryRepository: CategoryRepository,
    private val clock: Clock,
) : ViewModel() {
    val uiState: StateFlow<RecurringRulesUiState> = MutableStateFlow(RecurringRulesUiState(isLoading = false))

    private val _error = MutableStateFlow<Int?>(null)
    val error: StateFlow<Int?> = _error

    fun stop(rule: RecurrenceRule) = Unit

    suspend fun saveRule(rule: RecurrenceRule, edited: FinanceTransaction): Boolean = false

    suspend fun add(transaction: FinanceTransaction, newRule: NewRecurrenceRule?): Boolean = false

    fun clearError() {
        _error.value = null
    }

    companion object {
        fun factory(
            recurrenceRepository: RecurrenceRepository,
            transactionRepository: TransactionRepository,
            categoryRepository: CategoryRepository,
            clock: Clock,
        ) = viewModelFactory {
            initializer { RecurringRulesViewModel(recurrenceRepository, transactionRepository, categoryRepository, clock) }
        }
    }
}
