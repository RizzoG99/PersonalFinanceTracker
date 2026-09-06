package com.rizzog99.personalfinancetracker.features.categories

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class CategorySettingsUiState(
    val categories: List<FinanceCategory> = emptyList(),
    val isLoading: Boolean = true,
)

class CategorySettingsViewModel(
    private val categoryRepository: CategoryRepository,
) : ViewModel() {
    val uiState: StateFlow<CategorySettingsUiState> = categoryRepository.observeAll()
        .map { categories -> CategorySettingsUiState(categories = categories, isLoading = false) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), CategorySettingsUiState())

    init {
        viewModelScope.launch { categoryRepository.seedDefaultsIfEmpty() }
    }

    suspend fun add(category: NewCategory): Boolean = runCatching {
        categoryRepository.add(category)
    }.isSuccess

    suspend fun update(category: FinanceCategory): Boolean = runCatching {
        categoryRepository.update(category)
    }.isSuccess

    suspend fun delete(category: FinanceCategory): Boolean = runCatching {
        categoryRepository.delete(category.id)
    }.isSuccess

    companion object {
        fun factory(categoryRepository: CategoryRepository) = viewModelFactory {
            initializer { CategorySettingsViewModel(categoryRepository) }
        }
    }
}
