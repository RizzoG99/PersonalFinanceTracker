package com.rizzog99.personalfinancetracker.features.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.data.preferences.ReceiptCategoryMapRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.receipt.ReceiptCategoryConcept
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class ScanCategoriesUiState(
    val categories: List<FinanceCategory> = emptyList(),
    /** concept key -> category id. */
    val pairings: Map<String, String> = emptyMap(),
    val isLoading: Boolean = true,
)

class ScanCategoriesViewModel(
    private val categoryRepository: CategoryRepository,
    private val receiptCategoryMapRepository: ReceiptCategoryMapRepository,
) : ViewModel() {
    val uiState: StateFlow<ScanCategoriesUiState> = combine(
        categoryRepository.observeAll(),
        receiptCategoryMapRepository.pairings,
    ) { categories, pairings ->
        // Prune on read rather than on category deletion: this screen is the only place the stale
        // pairing would be visible, and it keeps the category repository from having to know this
        // feature exists.
        val live = categories.map { it.id }.toSet()
        ScanCategoriesUiState(
            categories = categories,
            pairings = pairings.filterValues { it in live },
            isLoading = false,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ScanCategoriesUiState())

    /** Passing null clears the pairing, putting the concept back on automatic matching. */
    fun pair(concept: ReceiptCategoryConcept, categoryId: String?) {
        // viewModelScope, not the composable's scope: navigating back immediately after tapping
        // must not cancel the write.
        viewModelScope.launch { receiptCategoryMapRepository.setCategoryId(categoryId, concept) }
    }

    companion object {
        fun factory(
            categoryRepository: CategoryRepository,
            receiptCategoryMapRepository: ReceiptCategoryMapRepository,
        ) = viewModelFactory {
            initializer { ScanCategoriesViewModel(categoryRepository, receiptCategoryMapRepository) }
        }
    }
}
