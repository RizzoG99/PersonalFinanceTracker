package com.rizzog99.personalfinancetracker.features.activity

import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionTypeFilter
import com.rizzog99.personalfinancetracker.domain.transaction.SearchDateRange
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionFilters
import java.math.BigDecimal
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityScreen() {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val viewModel: ActivityViewModel = viewModel(
        factory = ActivityViewModel.factory(
            transactionRepository = application.transactionRepository,
            categoryRepository = application.categoryRepository,
        ),
    )
    val state by viewModel.uiState.collectAsState()
    val error by viewModel.error.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var editingTransaction by remember { mutableStateOf<FinanceTransaction?>(null) }
    var isCreating by remember { mutableStateOf(false) }
    var deletingTransaction by remember { mutableStateOf<FinanceTransaction?>(null) }
    var recurringDeletionTransaction by remember { mutableStateOf<FinanceTransaction?>(null) }
    var filtersVisible by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.activity_title)) },
                actions = {
                    IconButton(onClick = { filtersVisible = true }) {
                        Icon(Icons.Outlined.Tune, contentDescription = stringResource(R.string.filters))
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { isCreating = true },
                content = {
                    Icon(
                        imageVector = Icons.Outlined.Add,
                        contentDescription = stringResource(R.string.add_transaction),
                    )
                },
            )
        },
    ) { innerPadding ->
        ActivityContent(
            state = state,
            error = error,
            onSearchChange = viewModel::updateSearch,
            onTypeFilterChange = viewModel::updateTypeFilter,
            onClearError = viewModel::clearError,
            onClearFilters = viewModel::clearFilters,
            onAdd = { isCreating = true },
            onEdit = { editingTransaction = it },
            onDelete = {
                if (it.recurrenceRuleId == null) deletingTransaction = it else recurringDeletionTransaction = it
            },
            modifier = Modifier.padding(innerPadding),
        )
    }

    if (filtersVisible) {
        ActivityFiltersSheet(
            filters = state.filters,
            categories = state.categories,
            onDismiss = { filtersVisible = false },
            onApply = {
                viewModel.updateFilters(it)
                filtersVisible = false
            },
        )
    }

    if (isCreating || editingTransaction != null) {
        TransactionEditorSheet(
            editingTransaction = editingTransaction,
            categories = state.categories,
            onDismiss = {
                isCreating = false
                editingTransaction = null
            },
            onSave = { transaction ->
                scope.launch {
                    if (viewModel.save(transaction)) {
                        isCreating = false
                        editingTransaction = null
                        snackbarHostState.showSnackbar(
                            message = if (transaction.id == editingTransaction?.id) {
                                application.getString(R.string.transaction_updated)
                            } else {
                                application.getString(R.string.transaction_added)
                            },
                        )
                    }
                }
            },
        )
    }

    deletingTransaction?.let { transaction ->
        DeleteTransactionDialog(
            onDismiss = { deletingTransaction = null },
            onConfirm = {
                deletingTransaction = null
                scope.launch {
                    if (viewModel.delete(transaction)) {
                        val result = snackbarHostState.showSnackbar(
                            message = application.getString(R.string.transaction_deleted),
                            actionLabel = application.getString(R.string.undo),
                        )
                        if (result == SnackbarResult.ActionPerformed) viewModel.save(transaction)
                    }
                }
            },
        )
    }

    recurringDeletionTransaction?.let { transaction ->
        RecurringDeleteDialog(
            onDismiss = { recurringDeletionTransaction = null },
            onDeleteThisOnly = {
                recurringDeletionTransaction = null
                scope.launch {
                    if (viewModel.delete(transaction)) showUndoDeletion(snackbarHostState, viewModel, transaction, application)
                }
            },
            onDeleteThisAndFuture = {
                recurringDeletionTransaction = null
                scope.launch { viewModel.deleteThisAndFuture(transaction) }
            },
        )
    }
}

@Composable
private fun ActivityContent(
    state: ActivityUiState,
    error: String?,
    onSearchChange: (String) -> Unit,
    onTypeFilterChange: (TransactionTypeFilter) -> Unit,
    onClearError: () -> Unit,
    onClearFilters: () -> Unit,
    onAdd: () -> Unit,
    onEdit: (FinanceTransaction) -> Unit,
    onDelete: (FinanceTransaction) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            OutlinedTextField(
                value = state.searchText,
                onValueChange = onSearchChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.search_transactions)) },
                leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
                singleLine = true,
            )
        }
        item {
            TransactionTypeFilters(
                selected = state.filters.type,
                onSelected = onTypeFilterChange,
            )
        }
        if (error != null) {
            item {
                Card {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(error, modifier = Modifier.weight(1f))
                        TextButton(onClick = onClearError) { Text(stringResource(R.string.dismiss)) }
                    }
                }
            }
        }
        when {
            state.allTransactions.isEmpty() -> item {
                EmptyStateWithAction(onAdd = onAdd)
            }
            state.visibleTransactions.isEmpty() -> item {
                NoResultsState(onClear = {
                    onSearchChange("")
                    onClearFilters()
                })
            }
            else -> items(state.visibleTransactions, key = FinanceTransaction::id) { transaction ->
                TransactionRow(
                    transaction = transaction,
                    onEdit = { onEdit(transaction) },
                    onDelete = { onDelete(transaction) },
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TransactionTypeFilters(
    selected: TransactionTypeFilter,
    onSelected: (TransactionTypeFilter) -> Unit,
) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf(
            TransactionTypeFilter.ALL to R.string.filter_all,
            TransactionTypeFilter.INCOME to R.string.filter_income,
            TransactionTypeFilter.EXPENSE to R.string.filter_expense,
        ).forEach { (filter, labelRes) ->
            FilterChip(
                selected = selected == filter,
                onClick = { onSelected(filter) },
                label = { Text(stringResource(labelRes)) },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun ActivityFiltersSheet(
    filters: TransactionFilters,
    categories: List<FinanceCategory>,
    onDismiss: () -> Unit,
    onApply: (TransactionFilters) -> Unit,
) {
    var selectedCategories by remember(filters) { mutableStateOf(filters.categories) }
    var selectedDateRange by remember(filters) { mutableStateOf(filters.dateRange) }
    var minimum by remember(filters) { mutableStateOf(filters.amountMin?.toPlainString().orEmpty()) }
    var maximum by remember(filters) { mutableStateOf(filters.amountMax?.toPlainString().orEmpty()) }
    var recurringOnly by remember(filters) { mutableStateOf(filters.recurringOnly) }
    val minimumAmount = minimum.replace(',', '.').toBigDecimalOrNull()
    val maximumAmount = maximum.replace(',', '.').toBigDecimalOrNull()
    val amountsValid = (minimum.isBlank() || minimumAmount != null) &&
        (maximum.isBlank() || maximumAmount != null) &&
        (minimumAmount == null || maximumAmount == null || minimumAmount <= maximumAmount)

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = stringResource(R.string.filters),
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.semantics { heading() },
            )
            Text(stringResource(R.string.date_range), style = MaterialTheme.typography.titleMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    null to R.string.filter_any_date,
                    SearchDateRange.ThisMonth to R.string.filter_this_month,
                    SearchDateRange.Last3Months to R.string.filter_last_three_months,
                    SearchDateRange.ThisYear to R.string.filter_this_year,
                ).forEach { (range, label) ->
                    FilterChip(
                        selected = selectedDateRange == range,
                        onClick = { selectedDateRange = range },
                        label = { Text(stringResource(label)) },
                    )
                }
            }
            Text(stringResource(R.string.amount_range), style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                value = minimum,
                onValueChange = { minimum = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.minimum_amount)) },
                singleLine = true,
            )
            OutlinedTextField(
                value = maximum,
                onValueChange = { maximum = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.maximum_amount)) },
                isError = !amountsValid,
                supportingText = { if (!amountsValid) Text(stringResource(R.string.invalid_amount_range)) },
                singleLine = true,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = recurringOnly, onCheckedChange = { recurringOnly = it })
                Text(stringResource(R.string.recurring_only))
            }
            Text(stringResource(R.string.categories), style = MaterialTheme.typography.titleMedium)
            categories.forEach { category ->
                Row(
                    modifier = Modifier.fillMaxWidth().clickable {
                        selectedCategories = if (category.name in selectedCategories) {
                            selectedCategories - category.name
                        } else {
                            selectedCategories + category.name
                        }
                    },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Checkbox(
                        checked = category.name in selectedCategories,
                        onCheckedChange = { checked ->
                            selectedCategories = if (checked) selectedCategories + category.name else selectedCategories - category.name
                        },
                    )
                    Text(category.name)
                }
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = { onApply(TransactionFilters()) }) { Text(stringResource(R.string.clear_filters)) }
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = {
                        onApply(
                            filters.copy(
                                categories = selectedCategories,
                                dateRange = selectedDateRange,
                                amountMin = minimumAmount,
                                amountMax = maximumAmount,
                                recurringOnly = recurringOnly,
                            ),
                        )
                    },
                    enabled = amountsValid,
                ) { Text(stringResource(R.string.apply_filters)) }
            }
        }
    }
}

@Composable
private fun TransactionRow(
    transaction: FinanceTransaction,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    Card {
        ListItem(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(role = Role.Button, onClick = onEdit),
            headlineContent = { Text(transaction.note.ifBlank { transaction.categoryLabel }) },
            supportingContent = {
                Text("${transaction.categoryLabel} · ${formatDate(transaction.timestamp)}")
            },
            trailingContent = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = formatAmount(transaction.amount, transaction.currencyCode),
                        color = if (transaction.amount < BigDecimal.ZERO) {
                            MaterialTheme.colorScheme.error
                        } else {
                            MaterialTheme.colorScheme.primary
                        },
                        fontFamily = FontFamily.Monospace,
                    )
                    Spacer(Modifier.width(4.dp))
                    IconButton(onClick = onEdit) {
                        Icon(Icons.Outlined.Edit, contentDescription = stringResource(R.string.edit_transaction))
                    }
                    IconButton(onClick = onDelete) {
                        Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.delete_transaction))
                    }
                }
            },
        )
    }
}

@Composable
private fun EmptyStateWithAction(onAdd: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 56.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = stringResource(R.string.empty_state_title),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.semantics { heading() },
        )
        Text(stringResource(R.string.empty_state_message))
        Button(onClick = onAdd) { Text(stringResource(R.string.add_transaction)) }
    }
}

@Composable
private fun NoResultsState(onClear: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 56.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = stringResource(R.string.no_matching_transactions),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.semantics { heading() },
        )
        Text(stringResource(R.string.no_matching_transactions_message))
        OutlinedButton(onClick = onClear) { Text(stringResource(R.string.clear_filters)) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TransactionEditorSheet(
    editingTransaction: FinanceTransaction?,
    categories: List<FinanceCategory>,
    onDismiss: () -> Unit,
    onSave: (FinanceTransaction) -> Unit,
) {
    var amountText by remember(editingTransaction) {
        mutableStateOf(editingTransaction?.amount?.abs()?.toPlainString().orEmpty())
    }
    var note by remember(editingTransaction) { mutableStateOf(editingTransaction?.note.orEmpty()) }
    var selectedType by remember(editingTransaction, categories) {
        mutableStateOf(
            categories.firstOrNull { it.id == editingTransaction?.categoryId }?.type ?: TransactionType.EXPENSE,
        )
    }
    var selectedCategoryId by remember(editingTransaction, categories, selectedType) {
        mutableStateOf(
            editingTransaction?.categoryId?.takeIf { id -> categories.any { it.id == id } }
                ?: categories.firstOrNull { it.type == selectedType }?.id,
        )
    }
    var categoryMenuExpanded by remember { mutableStateOf(false) }
    val matchingCategories = categories.filter { it.type == selectedType }
    val selectedCategory = matchingCategories.firstOrNull { it.id == selectedCategoryId }
    val amount = amountText.replace(',', '.').toBigDecimalOrNull()
    val canSave = amount != null && amount > BigDecimal.ZERO && selectedCategory != null

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = stringResource(if (editingTransaction == null) R.string.add_transaction else R.string.edit_transaction),
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.semantics { heading() },
            )
            OutlinedTextField(
                value = amountText,
                onValueChange = { amountText = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.amount)) },
                supportingText = { Text(stringResource(R.string.amount_must_be_positive)) },
                singleLine = true,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = selectedType == TransactionType.INCOME,
                    onClick = {
                        selectedType = TransactionType.INCOME
                        selectedCategoryId = categories.firstOrNull { it.type == selectedType }?.id
                    },
                    label = { Text(stringResource(R.string.filter_income)) },
                )
                FilterChip(
                    selected = selectedType == TransactionType.EXPENSE,
                    onClick = {
                        selectedType = TransactionType.EXPENSE
                        selectedCategoryId = categories.firstOrNull { it.type == selectedType }?.id
                    },
                    label = { Text(stringResource(R.string.filter_expense)) },
                )
            }
            Box {
                OutlinedButton(
                    onClick = { categoryMenuExpanded = true },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = matchingCategories.isNotEmpty(),
                ) {
                    Text(selectedCategory?.name ?: stringResource(R.string.select_category))
                }
                androidx.compose.material3.DropdownMenu(
                    expanded = categoryMenuExpanded,
                    onDismissRequest = { categoryMenuExpanded = false },
                ) {
                    matchingCategories.forEach { category ->
                        androidx.compose.material3.DropdownMenuItem(
                            text = { Text(category.name) },
                            onClick = {
                                selectedCategoryId = category.id
                                categoryMenuExpanded = false
                            },
                        )
                    }
                }
            }
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.note)) },
                supportingText = { Text(stringResource(R.string.note_optional)) },
            )
            Row(
                modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = {
                        val category = requireNotNull(selectedCategory)
                        val signedAmount = if (category.type == TransactionType.EXPENSE) amount!!.negate() else amount!!
                        onSave(
                            FinanceTransaction(
                                id = editingTransaction?.id ?: UUID.randomUUID().toString(),
                                timestamp = editingTransaction?.timestamp ?: Instant.now(),
                                amount = signedAmount,
                                note = note.trim(),
                                categoryLabel = category.name,
                                categoryId = category.id,
                                currencyCode = category.currencyCode,
                                goalId = editingTransaction?.goalId,
                                recurrenceRuleId = editingTransaction?.recurrenceRuleId,
                            ),
                        )
                    },
                    enabled = canSave,
                ) {
                    Text(stringResource(R.string.save))
                }
            }
        }
    }
}

@Composable
private fun DeleteTransactionDialog(onDismiss: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.delete_transaction_confirmation_title)) },
        text = { Text(stringResource(R.string.delete_transaction_confirmation_message)) },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
        confirmButton = {
            TextButton(onClick = onConfirm) { Text(stringResource(R.string.delete_transaction)) }
        },
    )
}

@Composable
private fun RecurringDeleteDialog(
    onDismiss: () -> Unit,
    onDeleteThisOnly: () -> Unit,
    onDeleteThisAndFuture: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.recurring_delete_title)) },
        text = { Text(stringResource(R.string.recurring_delete_message)) },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
        confirmButton = {
            Column(horizontalAlignment = Alignment.End) {
                TextButton(onClick = onDeleteThisOnly) { Text(stringResource(R.string.delete_this_transaction)) }
                TextButton(onClick = onDeleteThisAndFuture) { Text(stringResource(R.string.delete_this_and_future)) }
            }
        },
    )
}

private suspend fun showUndoDeletion(
    snackbarHostState: SnackbarHostState,
    viewModel: ActivityViewModel,
    transaction: FinanceTransaction,
    application: PersonalFinanceApplication,
) {
    val result = snackbarHostState.showSnackbar(
        message = application.getString(R.string.transaction_deleted),
        actionLabel = application.getString(R.string.undo),
    )
    if (result == SnackbarResult.ActionPerformed) viewModel.save(transaction)
}

private fun formatAmount(amount: BigDecimal, currencyCode: String): String {
    val formatter = NumberFormat.getCurrencyInstance(Locale.getDefault()).apply { currency = java.util.Currency.getInstance(currencyCode) }
    val sign = if (amount >= BigDecimal.ZERO) "+" else "−"
    return sign + formatter.format(amount.abs())
}

private fun formatDate(timestamp: Instant): String = DateTimeFormatter
    .ofLocalizedDate(java.time.format.FormatStyle.MEDIUM)
    .withLocale(Locale.getDefault())
    .withZone(ZoneId.systemDefault())
    .format(timestamp)
