package com.rizzog99.personalfinancetracker.features.recurring

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.ReceiptMappingRepository
import com.rizzog99.personalfinancetracker.data.repository.RecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.duplicateRuleIds
import com.rizzog99.personalfinancetracker.domain.recurrence.isActive
import com.rizzog99.personalfinancetracker.domain.recurrence.monthlySpend
import com.rizzog99.personalfinancetracker.domain.recurrence.nextOccurrence
import com.rizzog99.personalfinancetracker.domain.recurrence.title
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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

/** The Recurring screen (#294): rules, not the transactions they produced (iOS `RecurringView.swift`). */
class RecurringRulesViewModel(
    private val recurrenceRepository: RecurrenceRepository,
    private val transactionRepository: TransactionRepository,
    private val categoryRepository: CategoryRepository,
    private val clock: Clock,
    private val receiptMappingRepository: ReceiptMappingRepository? = null,
) : ViewModel() {
    /** Stopped here but maybe not written yet: hidden at once, so the row leaves with the swipe (#253). */
    private val stoppedIds = MutableStateFlow<Set<String>>(emptySet())

    val uiState: StateFlow<RecurringRulesUiState> = combine(
        recurrenceRepository.observeAll(),
        categoryRepository.observeAll(),
        stoppedIds,
    ) { rules, categories, stopped ->
        val now = clock.instant()
        val active = rules.filter { it.isActive(now) && it.id !in stopped }
        val duplicates = duplicateRuleIds(active)
        val rows = active.map { rule ->
            RecurringRuleRow(
                rule = rule,
                title = rule.title(),
                nextDate = rule.nextOccurrence(now, clock.zone),
                isDuplicate = rule.id in duplicates,
                category = categories.firstOrNull { it.id == rule.categoryId },
            )
        }.sortedWith(compareBy<RecurringRuleRow, Instant?>(nullsLast()) { it.nextDate }.thenBy { it.title.lowercase() })
        RecurringRulesUiState(isLoading = false, rows = rows, monthlySpend = monthlySpend(active), categories = categories)
    }
        // A failed read shows an empty list, as iOS's `try?` does; it never escapes the scope (#133).
        .catch { emit(RecurringRulesUiState(isLoading = false)) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), RecurringRulesUiState())

    /** A string resource id, never the throwable's text (#135). */
    private val _error = MutableStateFlow<Int?>(null)
    val error: StateFlow<Int?> = _error

    /** Stops future occurrences only; already-recorded transactions stay (iOS `closeRecurrenceRule`). */
    fun stop(rule: RecurrenceRule) {
        stoppedIds.update { it + rule.id }
        viewModelScope.launch {
            try {
                recurrenceRepository.stop(rule.id, clock.instant())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                stoppedIds.update { it - rule.id }
                _error.value = R.string.activity_update_failed
            }
        }
    }

    /** Rule-edit save: the template fields of [edited]; cadence and start stay (iOS `saveRuleEdits`). */
    suspend fun saveRule(rule: RecurrenceRule, edited: FinanceTransaction): Boolean = write {
        recurrenceRepository.updateTemplate(rule.id, edited.amount, edited.note, edited.categoryLabel, edited.categoryId, edited.currencyCode)
    }

    /** "+": the shell's add path (`PersonalFinanceNavHost` onSave), Repeat preset on. */
    suspend fun add(transaction: FinanceTransaction, newRule: NewRecurrenceRule?, receiptMerchant: String? = null): Boolean {
        val saved = write {
            if (newRule != null) recurrenceRepository.createAndMaterialize(newRule) else transactionRepository.upsert(transaction)
        }
        if (saved && receiptMerchant != null && transaction.categoryId != null) {
            // Best effort: failing to learn the merchant never undoes the save.
            try {
                receiptMappingRepository?.remember(receiptMerchant, transaction.categoryId)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
            }
        }
        return saved
    }

    fun clearError() {
        _error.value = null
    }

    /** Main-thread return, as ActivityViewModel.write (#417); only a resource id reaches the screen. */
    private suspend fun write(block: suspend () -> Unit): Boolean = withContext(Dispatchers.Main.immediate) {
        try {
            block()
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _error.value = R.string.activity_update_failed
            false
        }
    }

    companion object {
        fun factory(
            recurrenceRepository: RecurrenceRepository,
            transactionRepository: TransactionRepository,
            categoryRepository: CategoryRepository,
            clock: Clock,
            receiptMappingRepository: ReceiptMappingRepository,
        ) = viewModelFactory {
            initializer {
                RecurringRulesViewModel(recurrenceRepository, transactionRepository, categoryRepository, clock, receiptMappingRepository)
            }
        }
    }
}
