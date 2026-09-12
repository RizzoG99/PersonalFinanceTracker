package com.rizzog99.personalfinancetracker.features.data

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.combine

data class DataTransferUiState(val transactions: List<FinanceTransaction> = emptyList(), val categories: List<FinanceCategory> = emptyList())

class DataTransferViewModel(private val repository: TransactionRepository, private val categoryRepository: CategoryRepository) : ViewModel() {
    val uiState: StateFlow<DataTransferUiState> = combine(repository.observeAll(), categoryRepository.observeAll(), ::DataTransferUiState)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DataTransferUiState())

    fun import(transactions: List<FinanceTransaction>, categorySelections: Map<String, String?>, onFinished: (Boolean) -> Unit) = viewModelScope.launch {
        onFinished(runCatching {
            val known = uiState.value.categories.associateBy(FinanceCategory::id).toMutableMap()
            val created = categorySelections.filterValues { it == null }.keys.associateWith { label ->
                val type = if (transactions.any { it.categoryLabel == label && it.amount.signum() < 0 }) TransactionType.EXPENSE else TransactionType.INCOME
                categoryRepository.add(NewCategory(name = label.forCategoryName(), iconToken = "tag", type = type)).also { known[it.id] = it }
            }
            repository.insertBatch(transactions.map { transaction ->
                categorySelections[transaction.categoryLabel]?.let(known::get)?.let { category ->
                    transaction.copy(categoryId = category.id, categoryLabel = category.name)
                } ?: created[transaction.categoryLabel]?.let { category -> transaction.copy(categoryId = category.id, categoryLabel = category.name) } ?: transaction
            })
        }.isSuccess)
    }

    companion object {
        fun factory(repository: TransactionRepository, categoryRepository: CategoryRepository) = viewModelFactory {
            initializer { DataTransferViewModel(repository, categoryRepository) }
        }
    }
}

private fun String.forCategoryName(): String = filter { character ->
    character.isLetterOrDigit() || character.isWhitespace() || character in setOf('&', '/', '-', '\'', '.', ',', '(', ')')
}.trim().ifBlank { "Other" }
