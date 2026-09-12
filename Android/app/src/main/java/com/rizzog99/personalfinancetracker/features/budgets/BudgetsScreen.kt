package com.rizzog99.personalfinancetracker.features.budgets

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.money.AmountInput
import com.rizzog99.personalfinancetracker.features.categories.categoryColor
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.components.categoryIconFor
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinanceExtendedColors
import java.math.BigDecimal
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import androidx.lifecycle.viewModelScope

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BudgetsScreen(onBack: () -> Unit) {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val viewModel: BudgetsViewModel = viewModel(
        factory = BudgetsViewModel.factory(application.categoryRepository),
    )
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = stringResource(R.string.budgets_title),
                        modifier = Modifier.semantics { heading() },
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = androidx.compose.ui.graphics.Color.Transparent,
                    titleContentColor = MaterialTheme.colorScheme.onBackground,
                    navigationIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
            )
        },
        containerColor = androidx.compose.ui.graphics.Color.Transparent,
    ) { padding ->
        BudgetContent(
            categories = state.categories,
            onBudgetChanged = viewModel::updateBudget,
            modifier = Modifier.padding(padding),
        )
    }
}

@Composable
private fun BudgetContent(
    categories: List<FinanceCategory>,
    onBudgetChanged: (FinanceCategory, BigDecimal?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val expenseCategories = categories.filter { it.type == TransactionType.EXPENSE }.sortedBy { it.name }
    val totalBudgeted = expenseCategories.sumOf { it.monthlyBudget ?: BigDecimal.ZERO }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text(
                text = stringResource(R.string.monthly_budget_expense_categories),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.outline,
                modifier = Modifier.padding(start = 4.dp, top = 8.dp).semantics { heading() },
            )
        }
        items(expenseCategories, key = FinanceCategory::id) { category ->
            BudgetRow(category = category, onBudgetChanged = onBudgetChanged)
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.total_budgeted),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.outline,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = formatCurrency(totalBudgeted, "EUR"),
                    style = MaterialTheme.typography.labelLarge,
                )
            }
        }
    }
}

@Composable
private fun BudgetRow(
    category: FinanceCategory,
    onBudgetChanged: (FinanceCategory, BigDecimal?) -> Unit,
) {
    var text by remember(category.id, category.monthlyBudget) {
        mutableStateOf(category.monthlyBudget?.takeIf { it > BigDecimal.ZERO }?.toPlainString().orEmpty())
    }
    var focused by remember { mutableStateOf(false) }

    fun commit() {
        val value = AmountInput.parse(text)
        when {
            text.isBlank() -> onBudgetChanged(category, null)
            value != null && value > BigDecimal.ZERO -> onBudgetChanged(category, value)
            else -> text = category.monthlyBudget?.takeIf { it > BigDecimal.ZERO }?.toPlainString().orEmpty()
        }
    }

    FinanceCard {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { focused = true }
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = categoryIconFor(category.iconToken),
                contentDescription = null,
                tint = categoryColor(category.colorToken),
            )
            Text(category.name, modifier = Modifier.padding(start = 12.dp).weight(1f))
            TextField(
                value = if (focused) text else category.monthlyBudget?.takeIf { it > BigDecimal.ZERO }?.let { formatCurrency(it, category.currencyCode) }.orEmpty(),
                onValueChange = { text = AmountInput.sanitize(it) },
                modifier = Modifier
                    .width(128.dp)
                    .onFocusChanged { focusState ->
                        if (focused && !focusState.isFocused) commit()
                        focused = focusState.isFocused
                    },
                placeholder = { Text(stringResource(R.string.no_limit)) },
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(textAlign = TextAlign.End),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    focusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                    unfocusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                    disabledIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                ),
            )
        }
    }
}

private data class BudgetsUiState(val categories: List<FinanceCategory> = emptyList())

private class BudgetsViewModel(
    private val categoryRepository: CategoryRepository,
) : ViewModel() {
    val uiState: StateFlow<BudgetsUiState> = categoryRepository.observeAll()
        .map(::BudgetsUiState)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), BudgetsUiState())

    fun updateBudget(category: FinanceCategory, budget: BigDecimal?) {
        viewModelScope.launch {
            categoryRepository.update(category.copy(monthlyBudget = budget))
        }
    }

    companion object {
        fun factory(categoryRepository: CategoryRepository) = viewModelFactory {
            initializer { BudgetsViewModel(categoryRepository) }
        }
    }
}
