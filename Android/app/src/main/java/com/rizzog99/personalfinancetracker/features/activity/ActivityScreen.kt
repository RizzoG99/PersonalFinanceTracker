package com.rizzog99.personalfinancetracker.features.activity

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import android.content.res.Configuration
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DateRangePicker
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
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.rememberDateRangePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.receipt.ReceiptParser
import com.rizzog99.personalfinancetracker.domain.receipt.ReceiptScan
import com.rizzog99.personalfinancetracker.domain.receipt.ReceiptTextRecognizer
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionTypeFilter
import com.rizzog99.personalfinancetracker.domain.transaction.SearchDateRange
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionFilters
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.components.categoryIconFor
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatSignedCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatTransactionDate
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinancePalette
import java.math.BigDecimal
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityScreen(
    startCreating: Boolean = false,
    onStartCreatingConsumed: () -> Unit = {},
    returnToDashboardAfterCreation: Boolean = false,
    onDashboardCreationFinished: () -> Unit = {},
) {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val viewModel: ActivityViewModel = viewModel(
        factory = ActivityViewModel.factory(
            transactionRepository = application.transactionRepository,
            categoryRepository = application.categoryRepository,
            recurrenceRepository = application.recurrenceRepository,
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
    var recurringEditTransaction by remember { mutableStateOf<FinanceTransaction?>(null) }
    var filtersVisible by remember { mutableStateOf(false) }
    val isLandscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE

    LaunchedEffect(startCreating) {
        if (startCreating) {
            isCreating = true
            onStartCreatingConsumed()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = stringResource(R.string.activity_title),
                        style = MaterialTheme.typography.displaySmall,
                        modifier = Modifier.semantics { heading() },
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
                    titleContentColor = MaterialTheme.colorScheme.onBackground,
                    actionIconContentColor = LocalFinancePalette.current.textMid,
                ),
                actions = {
                    if (isLandscape) {
                        IconButton(onClick = { isCreating = true }) {
                            Icon(
                                imageVector = Icons.Outlined.Add,
                                contentDescription = stringResource(R.string.add_transaction),
                            )
                        }
                    }
                    IconButton(onClick = { filtersVisible = true }) {
                        Icon(Icons.Outlined.Tune, contentDescription = stringResource(R.string.filters))
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = Color.Transparent,
        contentColor = MaterialTheme.colorScheme.onBackground,
        floatingActionButton = {
            if (!isLandscape) {
                FloatingActionButton(
                    onClick = { isCreating = true },
                    content = {
                        Icon(
                            imageVector = Icons.Outlined.Add,
                            contentDescription = stringResource(R.string.add_transaction),
                        )
                    },
                )
            }
        },
    ) { innerPadding ->
        ActivityContent(
            state = state,
            error = error,
            onSearchChange = viewModel::updateSearch,
            onTypeFilterChange = viewModel::updateTypeFilter,
            onClearError = viewModel::clearError,
            onClearFilters = viewModel::clearFilters,
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
            receiptMappingRepository = application.receiptMappingRepository,
            onDismiss = {
                val shouldReturnToDashboard = returnToDashboardAfterCreation && isCreating
                isCreating = false
                editingTransaction = null
                if (shouldReturnToDashboard) onDashboardCreationFinished()
            },
            onSave = { transaction, recurrenceRule, receiptMerchant ->
                if (editingTransaction?.recurrenceRuleId != null) {
                    recurringEditTransaction = transaction
                } else {
                    val wasEditing = editingTransaction != null
                    scope.launch {
                        val saved = recurrenceRule?.let { viewModel.createRecurringTransaction(it) } ?: viewModel.save(transaction)
                        if (saved) {
                            if (receiptMerchant != null && transaction.categoryId != null) {
                                application.receiptMappingRepository.remember(receiptMerchant, transaction.categoryId)
                            }
                            val shouldReturnToDashboard = returnToDashboardAfterCreation && isCreating
                            isCreating = false
                            editingTransaction = null
                            if (shouldReturnToDashboard) {
                                onDashboardCreationFinished()
                            } else {
                                snackbarHostState.showSnackbar(
                                    message = if (wasEditing) {
                                        application.getString(R.string.transaction_updated)
                                    } else {
                                        application.getString(R.string.transaction_added)
                                    },
                                )
                            }
                        }
                    }
                }
            },
        )
    }

    recurringEditTransaction?.let { transaction ->
        RecurringEditDialog(
            onDismiss = { recurringEditTransaction = null },
            onEditThisOnly = {
                recurringEditTransaction = null
                scope.launch {
                    if (viewModel.save(transaction)) {
                        val shouldReturnToDashboard = returnToDashboardAfterCreation && isCreating
                        isCreating = false
                        editingTransaction = null
                        if (shouldReturnToDashboard) {
                            onDashboardCreationFinished()
                        } else {
                            snackbarHostState.showSnackbar(
                                message = application.getString(R.string.transaction_updated),
                            )
                        }
                    }
                }
            },
            onEditThisAndFuture = {
                recurringEditTransaction = null
                scope.launch {
                    if (viewModel.updateThisAndFuture(transaction)) {
                        isCreating = false
                        editingTransaction = null
                        snackbarHostState.showSnackbar(application.getString(R.string.transaction_updated))
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
    onEdit: (FinanceTransaction) -> Unit,
    onDelete: (FinanceTransaction) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (state.allTransactions.isEmpty()) {
        EmptyActivityContent(
            searchText = state.searchText,
            filters = state.filters.type,
            error = error,
            onSearchChange = onSearchChange,
            onTypeFilterChange = onTypeFilterChange,
            onClearError = onClearError,
            modifier = modifier,
        )
        return
    }

    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 112.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            ActivityFilterControls(
                searchText = state.searchText,
                filters = state.filters.type,
                error = error,
                onSearchChange = onSearchChange,
                onTypeFilterChange = onTypeFilterChange,
                onClearError = onClearError,
            )
        }
        if (state.visibleTransactions.isNotEmpty()) {
            item { ActivitySummary(transactions = state.visibleTransactions) }
        }
        when {
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

@Composable
private fun EmptyActivityContent(
    searchText: String,
    filters: TransactionTypeFilter,
    error: String?,
    onSearchChange: (String) -> Unit,
    onTypeFilterChange: (TransactionTypeFilter) -> Unit,
    onClearError: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxHeight()
            .padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 112.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ActivityFilterControls(
            searchText = searchText,
            filters = filters,
            error = error,
            onSearchChange = onSearchChange,
            onTypeFilterChange = onTypeFilterChange,
            onClearError = onClearError,
        )
        Spacer(Modifier.weight(1f))
        EmptyActivityState()
        Spacer(Modifier.weight(0.55f))
    }
}

@Composable
private fun ActivityFilterControls(
    searchText: String,
    filters: TransactionTypeFilter,
    error: String?,
    onSearchChange: (String) -> Unit,
    onTypeFilterChange: (TransactionTypeFilter) -> Unit,
    onClearError: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        TextField(
            value = searchText,
            onValueChange = onSearchChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text(stringResource(R.string.search_transactions)) },
            leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
            singleLine = true,
            shape = RoundedCornerShape(28.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                disabledIndicatorColor = Color.Transparent,
            ),
        )
        TransactionTypeFilters(selected = filters, onSelected = onTypeFilterChange)
        if (error != null) {
            FinanceCard {
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
}

@Composable
private fun ActivitySummary(transactions: List<FinanceTransaction>) {
    val income = transactions.filter { it.amount > BigDecimal.ZERO }
        .fold(BigDecimal.ZERO) { total, transaction -> total + transaction.amount }
    val expenses = transactions.filter { it.amount < BigDecimal.ZERO }
        .fold(BigDecimal.ZERO) { total, transaction -> total + transaction.amount.abs() }
    val currencyCode = transactions.first().currencyCode
    val useVerticalCards = LocalDensity.current.fontScale >= 1.3f

    if (useVerticalCards) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ActivitySummaryCards(
                income = income,
                expenses = expenses,
                currencyCode = currencyCode,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    } else {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ActivitySummaryCards(
                income = income,
                expenses = expenses,
                currencyCode = currencyCode,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun ActivitySummaryCards(
    income: BigDecimal,
    expenses: BigDecimal,
    currencyCode: String,
    modifier: Modifier,
) {
    val palette = LocalFinancePalette.current
    ActivitySummaryAmount(
        modifier = modifier,
        label = stringResource(R.string.filter_income),
        value = formatSignedCurrency(income, currencyCode),
        color = palette.positive,
    )
    ActivitySummaryAmount(
        modifier = modifier,
        label = stringResource(R.string.filter_expense),
        value = if (expenses.signum() == 0) {
            formatCurrency(BigDecimal.ZERO, currencyCode)
        } else {
            formatSignedCurrency(expenses.negate(), currencyCode)
        },
        color = palette.negative,
        valueColor = if (expenses.signum() == 0) palette.textMid else palette.negative,
    )
}

@Composable
private fun ActivitySummaryAmount(
    label: String,
    value: String,
    color: Color,
    valueColor: Color = color,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier = modifier
            .border(1.dp, color.copy(alpha = 0.38f), shape)
            .background(color.copy(alpha = 0.14f), shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(label, style = MaterialTheme.typography.titleSmall, color = color)
        Text(
            text = value,
            style = MaterialTheme.typography.titleMedium,
            color = valueColor,
            fontFamily = FontFamily.Monospace,
        )
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
    var customDateRangeVisible by remember { mutableStateOf(false) }
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
                FilterChip(
                    selected = selectedDateRange is SearchDateRange.Custom,
                    onClick = { customDateRangeVisible = true },
                    label = { Text(stringResource(R.string.filter_custom)) },
                )
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

    if (customDateRangeVisible) {
        CustomDateRangePickerDialog(
            selectedDateRange = selectedDateRange as? SearchDateRange.Custom,
            onDismiss = { customDateRangeVisible = false },
            onApply = {
                selectedDateRange = it
                customDateRangeVisible = false
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CustomDateRangePickerDialog(
    selectedDateRange: SearchDateRange.Custom?,
    onDismiss: () -> Unit,
    onApply: (SearchDateRange.Custom) -> Unit,
) {
    val today = LocalDate.now()
    val defaultStart = selectedDateRange?.from ?: today.minusMonths(1)
    val defaultEnd = selectedDateRange?.to ?: today
    val pickerState = rememberDateRangePickerState(
        initialSelectedStartDateMillis = defaultStart.toUtcStartOfDayMillis(),
        initialSelectedEndDateMillis = defaultEnd.toUtcStartOfDayMillis(),
    )
    val selectedStart = pickerState.selectedStartDateMillis
    val selectedEnd = pickerState.selectedEndDateMillis

    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                enabled = selectedStart != null && selectedEnd != null,
                onClick = {
                    onApply(
                        SearchDateRange.Custom(
                            from = selectedStart!!.toUtcLocalDate(),
                            to = selectedEnd!!.toUtcLocalDate(),
                        ),
                    )
                },
            ) { Text(stringResource(R.string.apply_filters)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        },
    ) {
        DateRangePicker(
            state = pickerState,
            title = { Text(stringResource(R.string.custom_date_range)) },
            showModeToggle = false,
        )
    }
}

private fun LocalDate.toUtcStartOfDayMillis(): Long = atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

private fun Long.toUtcLocalDate(): LocalDate = Instant.ofEpochMilli(this).atZone(ZoneOffset.UTC).toLocalDate()

@Composable
private fun TransactionRow(
    transaction: FinanceTransaction,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    val amountColor = if (transaction.amount < BigDecimal.ZERO) {
        LocalFinancePalette.current.negative
    } else {
        LocalFinancePalette.current.positive
    }
    val largeText = LocalDensity.current.fontScale >= 1.3f

    FinanceCard {
        if (largeText) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button, onClick = onEdit)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(transaction.note.ifBlank { transaction.categoryLabel })
                        Text(
                            text = "${transaction.categoryLabel} · ${formatTransactionDate(transaction.timestamp)}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = LocalFinancePalette.current.textMid,
                        )
                    }
                    Spacer(Modifier.width(12.dp))
                    Text(
                        text = formatSignedCurrency(transaction.amount, transaction.currencyCode),
                        color = amountColor,
                        fontFamily = FontFamily.Monospace,
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                ) {
                    IconButton(onClick = onEdit) {
                        Icon(Icons.Outlined.Edit, contentDescription = stringResource(R.string.edit_transaction))
                    }
                    IconButton(onClick = onDelete) {
                        Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.delete_transaction))
                    }
                }
            }
        } else {
            ListItem(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button, onClick = onEdit),
                headlineContent = { Text(transaction.note.ifBlank { transaction.categoryLabel }) },
                supportingContent = {
                    Text("${transaction.categoryLabel} · ${formatTransactionDate(transaction.timestamp)}")
                },
                trailingContent = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = formatSignedCurrency(transaction.amount, transaction.currencyCode),
                            color = amountColor,
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
}

@Composable
private fun EmptyActivityState() {
    FinanceCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = Icons.Outlined.Add,
                contentDescription = null,
                modifier = Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Text(
                text = stringResource(R.string.empty_state_title),
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                text = stringResource(R.string.empty_state_message),
                style = MaterialTheme.typography.bodyLarge,
                color = LocalFinancePalette.current.textMid,
                textAlign = TextAlign.Center,
            )
        }
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

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun TransactionEditorSheet(
    editingTransaction: FinanceTransaction?,
    categories: List<FinanceCategory>,
    receiptMappingRepository: com.rizzog99.personalfinancetracker.data.repository.ReceiptMappingRepository,
    onDismiss: () -> Unit,
    onSave: (FinanceTransaction, NewRecurrenceRule?, String?) -> Unit,
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
    var repeats by remember { mutableStateOf(false) }
    var recurrenceFrequency by remember { mutableStateOf(RecurrenceFrequency.MONTHLY) }
    var recurrenceInterval by remember { mutableStateOf(1) }
    var categoryTouched by remember { mutableStateOf(false) }
    var receiptStatus by remember { mutableStateOf<String?>(null) }
    var receiptMerchant by remember { mutableStateOf<String?>(null) }
    var scannedAmountText by remember { mutableStateOf<String?>(null) }
    var receiptTotalCandidates by remember { mutableStateOf<List<BigDecimal>>(emptyList()) }
    var timestamp by remember(editingTransaction) { mutableStateOf(editingTransaction?.timestamp ?: Instant.now()) }
    var scannedDate by remember { mutableStateOf<LocalDate?>(null) }
    var datePickerVisible by remember { mutableStateOf(false) }
    val matchingCategories = categories.filter { it.type == selectedType }
    val selectedCategory = matchingCategories.firstOrNull { it.id == selectedCategoryId }
    val amount = amountText.replace(',', '.').toBigDecimalOrNull()
    val canSave = amount != null && amount > BigDecimal.ZERO && selectedCategory != null
    val receiptReviewMessage = stringResource(R.string.receipt_review_before_saving)
    val receiptAmbiguousMessage = stringResource(R.string.receipt_total_ambiguous)
    val receiptAmountUnreadableMessage = stringResource(R.string.receipt_amount_unreadable)
    val receiptDateClampedMessage = stringResource(R.string.receipt_date_clamped)
    val receiptUnreadableMessage = stringResource(R.string.receipt_unreadable)
    val submitTransaction: () -> Unit = {
        val category = requireNotNull(selectedCategory)
        val signedAmount = if (category.type == TransactionType.EXPENSE) amount!!.negate() else amount!!
        val transaction = FinanceTransaction(
            id = editingTransaction?.id ?: UUID.randomUUID().toString(),
            timestamp = timestamp,
            amount = signedAmount,
            note = note.trim(),
            categoryLabel = category.name,
            categoryId = category.id,
            currencyCode = category.currencyCode,
            goalId = editingTransaction?.goalId,
            recurrenceRuleId = editingTransaction?.recurrenceRuleId,
        )
        onSave(
            transaction,
            if (repeats) {
                NewRecurrenceRule(
                    frequency = recurrenceFrequency,
                    interval = recurrenceInterval,
                    startDate = transaction.timestamp,
                    amount = transaction.amount,
                    note = transaction.note,
                    categoryLabel = transaction.categoryLabel,
                    categoryId = transaction.categoryId,
                    currencyCode = transaction.currencyCode,
                    goalId = transaction.goalId,
                )
            } else {
                null
            },
            receiptMerchant,
        )
    }
    val sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
                Text(
                    text = stringResource(if (editingTransaction == null) R.string.add_transaction else R.string.edit_transaction),
                    style = MaterialTheme.typography.headlineSmall,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                IconButton(onClick = submitTransaction, enabled = canSave) {
                    Icon(
                        imageVector = Icons.Outlined.Check,
                        contentDescription = stringResource(if (editingTransaction == null) R.string.add_transaction else R.string.save),
                    )
                }
            }
            if (editingTransaction == null) {
                ReceiptCaptureAction(
                    onScan = { scan ->
                        val wasAmountScanned = amountText == scannedAmountText
                        if (amountText.isBlank() || wasAmountScanned) {
                            scan.total?.let {
                                amountText = it.toPlainString()
                                scannedAmountText = amountText
                            }
                        }
                        receiptTotalCandidates = scan.totalCandidates
                        val displayedDate = timestamp.atZone(ZoneId.systemDefault()).toLocalDate()
                        if ((displayedDate == LocalDate.now() || displayedDate == scannedDate) && !scan.dateWasClamped) {
                            scan.date?.let { date ->
                                timestamp = date.atTime(LocalTime.now()).atZone(ZoneId.systemDefault()).toInstant()
                                scannedDate = date
                            }
                        }
                        if (note.isBlank() || note == receiptMerchant.orEmpty()) {
                            scan.merchant?.let { note = it }
                        }
                        receiptMerchant = scan.merchant
                        if (!categoryTouched) {
                            val mappedCategoryId = scan.merchant?.let { receiptMappingRepository.categoryIdFor(it) }
                            val inferredCategory = categories.firstOrNull { it.id == mappedCategoryId }
                                ?: inferReceiptCategory(scan, categories, selectedType)
                            if (inferredCategory != null) {
                                selectedType = inferredCategory.type
                                selectedCategoryId = inferredCategory.id
                            }
                        }
                        receiptStatus = when {
                            scan.totalCandidates.isNotEmpty() -> receiptAmbiguousMessage
                            scan.total == null -> receiptAmountUnreadableMessage
                            scan.dateWasClamped -> receiptDateClampedMessage
                            else -> receiptReviewMessage
                        }
                    },
                    onFailure = { receiptStatus = receiptUnreadableMessage },
                )
            }
            receiptStatus?.let { status ->
                FinanceCard {
                    Text(
                        text = status,
                        modifier = Modifier.padding(12.dp),
                        color = LocalFinancePalette.current.textMid,
                    )
                }
            }
            if (receiptTotalCandidates.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    receiptTotalCandidates.forEach { candidate ->
                        FilterChip(
                            selected = false,
                            onClick = {
                                amountText = candidate.toPlainString()
                                scannedAmountText = amountText
                                receiptTotalCandidates = emptyList()
                                receiptStatus = receiptReviewMessage
                            },
                            label = { Text(formatCurrency(candidate, "EUR")) },
                        )
                    }
                }
            }
            TextField(
                value = amountText,
                onValueChange = { amountText = it },
                modifier = Modifier.fillMaxWidth().height(156.dp),
                leadingIcon = {
                    Text(
                        text = "€",
                        style = MaterialTheme.typography.displaySmall,
                        color = LocalFinancePalette.current.textMid,
                    )
                },
                placeholder = { Text("0", style = MaterialTheme.typography.displayLarge) },
                textStyle = MaterialTheme.typography.displayLarge.copy(
                    textAlign = TextAlign.End,
                    fontFamily = FontFamily.Monospace,
                ),
                singleLine = true,
                shape = RoundedCornerShape(36.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                ),
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(28.dp))
                    .padding(4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                TransactionTypeOption(
                    label = stringResource(R.string.filter_income),
                    selected = selectedType == TransactionType.INCOME,
                    onClick = {
                        selectedType = TransactionType.INCOME
                        selectedCategoryId = categories.firstOrNull { it.type == selectedType }?.id
                        categoryTouched = true
                    },
                    modifier = Modifier.weight(1f),
                )
                TransactionTypeOption(
                    label = stringResource(R.string.filter_expense),
                    selected = selectedType == TransactionType.EXPENSE,
                    onClick = {
                        selectedType = TransactionType.EXPENSE
                        selectedCategoryId = categories.firstOrNull { it.type == selectedType }?.id
                        categoryTouched = true
                    },
                    modifier = Modifier.weight(1f),
                )
            }
            Box {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = stringResource(R.string.categories),
                        style = MaterialTheme.typography.titleMedium,
                        color = LocalFinancePalette.current.textMid,
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        matchingCategories.forEach { category ->
                            CategoryPickerTile(
                                category = category,
                                selected = category.id == selectedCategoryId,
                                onClick = {
                                    selectedCategoryId = category.id
                                    categoryTouched = true
                                },
                            )
                        }
                        OutlinedButton(onClick = { categoryMenuExpanded = true }) {
                            Text(stringResource(R.string.select_category))
                        }
                    }
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
                                categoryTouched = true
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
            OutlinedButton(
                onClick = { datePickerVisible = true },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("${stringResource(R.string.transaction_date)}: ${formatTransactionDate(timestamp)}")
            }
            if (editingTransaction == null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.repeat_transaction), style = MaterialTheme.typography.titleMedium)
                        Text(
                            stringResource(R.string.repeat_transaction_detail),
                            style = MaterialTheme.typography.bodyMedium,
                            color = LocalFinancePalette.current.textMid,
                        )
                    }
                    Switch(
                        checked = repeats,
                        onCheckedChange = { repeats = it },
                    )
                }
                if (repeats) {
                    Text(
                        stringResource(R.string.repeats_every),
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        OutlinedButton(
                            onClick = { recurrenceInterval = (recurrenceInterval - 1).coerceAtLeast(1) },
                            enabled = recurrenceInterval > 1,
                        ) {
                            Icon(Icons.Outlined.Remove, contentDescription = stringResource(R.string.decrease_interval))
                        }
                        Text(
                            text = recurrenceInterval.toString(),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        OutlinedButton(onClick = { recurrenceInterval += 1 }) {
                            Icon(Icons.Outlined.Add, contentDescription = stringResource(R.string.increase_interval))
                        }
                        Spacer(Modifier.weight(1f))
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        RecurrenceFrequency.entries.forEach { frequency ->
                            FilterChip(
                                selected = recurrenceFrequency == frequency,
                                onClick = { recurrenceFrequency = frequency },
                                label = {
                                    Text(
                                        stringResource(
                                            when (frequency) {
                                                RecurrenceFrequency.WEEKLY -> R.string.recurrence_weekly
                                                RecurrenceFrequency.MONTHLY -> R.string.recurrence_monthly
                                                RecurrenceFrequency.YEARLY -> R.string.recurrence_yearly
                                            },
                                        ),
                                    )
                                },
                            )
                        }
                    }
                }
            }
        }
    }

    if (datePickerVisible) {
        val selectedDate = timestamp.atZone(ZoneId.systemDefault()).toLocalDate()
        val datePickerState = androidx.compose.material3.rememberDatePickerState(
            initialSelectedDateMillis = selectedDate.toUtcStartOfDayMillis(),
        )
        DatePickerDialog(
            onDismissRequest = { datePickerVisible = false },
            confirmButton = {
                TextButton(
                    enabled = datePickerState.selectedDateMillis != null,
                    onClick = {
                        val date = datePickerState.selectedDateMillis!!.toUtcLocalDate()
                        timestamp = date.atTime(LocalTime.now()).atZone(ZoneId.systemDefault()).toInstant()
                        scannedDate = null
                        datePickerVisible = false
                    },
                ) { Text(stringResource(R.string.done)) }
            },
            dismissButton = { TextButton(onClick = { datePickerVisible = false }) { Text(stringResource(R.string.cancel)) } },
        ) {
            androidx.compose.material3.DatePicker(state = datePickerState)
        }
    }
}

@Composable
private fun TransactionTypeOption(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    TextButton(
        onClick = onClick,
        modifier = modifier.background(
            if (selected) MaterialTheme.colorScheme.surface else Color.Transparent,
            RoundedCornerShape(24.dp),
        ),
    ) {
        Text(label, color = MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
private fun CategoryPickerTile(
    category: FinanceCategory,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(18.dp)
    Column(
        modifier = Modifier
            .width(108.dp)
            .height(120.dp)
            .background(
                if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.14f) else Color.Transparent,
                shape,
            )
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) MaterialTheme.colorScheme.primary else LocalFinancePalette.current.hairline,
                shape = shape,
            )
            .clickable(role = Role.RadioButton, onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = categoryIconFor(category.iconToken),
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        Text(
            text = category.name,
            style = MaterialTheme.typography.labelMedium,
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
    }
}

@Composable
private fun ReceiptCaptureAction(
    onScan: suspend (ReceiptScan) -> Unit,
    onFailure: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var sourcePickerVisible by remember { mutableStateOf(false) }
    var pendingCameraFile by remember { mutableStateOf<File?>(null) }

    fun recognize(uri: Uri, temporaryFile: File? = null) {
        scope.launch {
            try {
                val scan = ReceiptParser.parse(ReceiptTextRecognizer.recognize(context, uri))
                temporaryFile?.delete()
                onScan(scan)
            } catch (_: Exception) {
                temporaryFile?.delete()
                onFailure()
            }
        }
    }

    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) recognize(uri)
    }
    val cameraCapture = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        val file = pendingCameraFile
        pendingCameraFile = null
        if (success && file != null) {
            recognize(FileProvider.getUriForFile(context, "${context.packageName}.receipt-files", file), file)
        } else {
            file?.delete()
        }
    }

    TextButton(onClick = { sourcePickerVisible = true }) {
        Text(stringResource(R.string.scan_receipt))
    }

    if (sourcePickerVisible) {
        AlertDialog(
            onDismissRequest = { sourcePickerVisible = false },
            title = { Text(stringResource(R.string.scan_receipt)) },
            text = { Text(stringResource(R.string.receipt_privacy_detail)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        sourcePickerVisible = false
                        val directory = File(context.cacheDir, "receipt-capture").apply { mkdirs() }
                        val file = File(directory, "${UUID.randomUUID()}.jpg")
                        pendingCameraFile = file
                        cameraCapture.launch(
                            FileProvider.getUriForFile(context, "${context.packageName}.receipt-files", file),
                        )
                    },
                ) { Text(stringResource(R.string.take_photo)) }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        sourcePickerVisible = false
                        photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    },
                ) { Text(stringResource(R.string.choose_photo)) }
            },
        )
    }
}

private fun inferReceiptCategory(
    scan: ReceiptScan,
    categories: List<FinanceCategory>,
    transactionType: TransactionType,
): FinanceCategory? {
    val merchant = scan.merchant.orEmpty().lowercase()
    val keywords = when {
        listOf("supermerc", "market", "alimentari", "conad", "coop", "lidl", "esselunga").any(merchant::contains) -> listOf("grocer")
        listOf("farmacia", "pharma").any(merchant::contains) -> listOf("pharmacy", "health")
        listOf("eni", "q8", "ip ", "fuel", "benzina").any(merchant::contains) -> listOf("gas")
        listOf("bar", "caffe", "coffee").any(merchant::contains) -> listOf("coffee", "restaurant")
        listOf("ristor", "pizzeria", "trattoria").any(merchant::contains) -> listOf("restaurant", "takeout")
        else -> emptyList()
    }
    return categories.firstOrNull { category ->
        category.type == transactionType && keywords.any(category.name.lowercase()::contains)
    } ?: categories.firstOrNull { it.type == transactionType }
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

@Composable
private fun RecurringEditDialog(
    onDismiss: () -> Unit,
    onEditThisOnly: () -> Unit,
    onEditThisAndFuture: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.recurring_edit_title)) },
        text = { Text(stringResource(R.string.recurring_edit_message)) },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
        confirmButton = {
            Column(horizontalAlignment = Alignment.End) {
                TextButton(onClick = onEditThisOnly) { Text(stringResource(R.string.edit_this_transaction)) }
                TextButton(onClick = onEditThisAndFuture) { Text(stringResource(R.string.edit_this_and_future)) }
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
