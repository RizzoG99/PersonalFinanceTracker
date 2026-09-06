package com.rizzog99.personalfinancetracker.features.categories

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.automirrored.outlined.ShowChart
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.BusinessCenter
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.CardGiftcard
import androidx.compose.material.icons.outlined.Category
import androidx.compose.material.icons.outlined.Checkroom
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.DirectionsBus
import androidx.compose.material.icons.outlined.DirectionsCar
import androidx.compose.material.icons.outlined.Flight
import androidx.compose.material.icons.outlined.LocalGasStation
import androidx.compose.material.icons.outlined.LocalHospital
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.LocalDining
import androidx.compose.material.icons.outlined.LocalTaxi
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.Pets
import androidx.compose.material.icons.outlined.PhoneIphone
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Restaurant
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.outlined.ShoppingBag
import androidx.compose.material.icons.outlined.ShoppingCart
import androidx.compose.material.icons.outlined.SportsEsports
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.Tv
import androidx.compose.material.icons.outlined.Work
import androidx.compose.material.icons.outlined.EmojiEvents
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
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
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.CategoryNameValidator
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinancePalette
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CategorySettingsScreen(onBack: () -> Unit) {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val viewModel: CategorySettingsViewModel = viewModel(
        factory = CategorySettingsViewModel.factory(application.categoryRepository),
    )
    val state by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var creating by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<FinanceCategory?>(null) }
    var deleting by remember { mutableStateOf<FinanceCategory?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = stringResource(R.string.category_settings_title),
                        modifier = Modifier.semantics { heading() },
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Outlined.ArrowBack,
                            contentDescription = stringResource(R.string.back),
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { creating = true }) {
                        Icon(
                            imageVector = Icons.Outlined.Add,
                            contentDescription = stringResource(R.string.add_category),
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = androidx.compose.ui.graphics.Color.Transparent,
                    titleContentColor = MaterialTheme.colorScheme.onBackground,
                    navigationIconContentColor = LocalFinancePalette.current.textMid,
                    actionIconContentColor = LocalFinancePalette.current.textMid,
                ),
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = androidx.compose.ui.graphics.Color.Transparent,
    ) { innerPadding ->
        CategorySettingsContent(
            state = state,
            onAdd = { creating = true },
            onEdit = { editing = it },
            modifier = Modifier.padding(innerPadding),
        )
    }

    if (creating) {
        CategoryEditorSheet(
            category = null,
            existingCategories = state.categories,
            onDismiss = { creating = false },
            onSaveNew = { category ->
                scope.launch {
                    if (viewModel.add(category)) {
                        creating = false
                    } else {
                        snackbarHostState.showSnackbar(application.getString(R.string.category_save_error))
                    }
                }
            },
            onSaveExisting = {},
            onDelete = {},
        )
    }

    editing?.let { category ->
        CategoryEditorSheet(
            category = category,
            existingCategories = state.categories,
            onDismiss = { editing = null },
            onSaveNew = {},
            onSaveExisting = { updated ->
                scope.launch {
                    if (viewModel.update(updated)) {
                        editing = null
                    } else {
                        snackbarHostState.showSnackbar(application.getString(R.string.category_save_error))
                    }
                }
            },
            onDelete = { deleting = category },
        )
    }

    deleting?.let { category ->
        DeleteCategoryDialog(
            category = category,
            onDismiss = { deleting = null },
            onConfirm = {
                deleting = null
                editing = null
                scope.launch {
                    if (!viewModel.delete(category)) {
                        snackbarHostState.showSnackbar(application.getString(R.string.category_save_error))
                    }
                }
            },
        )
    }
}

@Composable
private fun CategorySettingsContent(
    state: CategorySettingsUiState,
    onAdd: () -> Unit,
    onEdit: (FinanceCategory) -> Unit,
    modifier: Modifier = Modifier,
) {
    val expenseCategories = state.categories.filter { it.type == TransactionType.EXPENSE }
    val incomeCategories = state.categories.filter { it.type == TransactionType.INCOME }

    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        when {
            state.isLoading -> item {
                Text(
                    text = stringResource(R.string.loading),
                    color = LocalFinancePalette.current.textMid,
                    modifier = Modifier.padding(vertical = 24.dp),
                )
            }
            state.categories.isEmpty() -> item {
                EmptyCategoriesState(onAdd = onAdd)
            }
            else -> {
                item { CategorySectionTitle(R.string.expense_categories) }
                items(expenseCategories, key = FinanceCategory::id) { category ->
                    CategoryRow(category = category, onEdit = { onEdit(category) })
                }
                item { CategorySectionTitle(R.string.income_categories) }
                items(incomeCategories, key = FinanceCategory::id) { category ->
                    CategoryRow(category = category, onEdit = { onEdit(category) })
                }
            }
        }
    }
}

@Composable
private fun CategorySectionTitle(textRes: Int) {
    Text(
        text = stringResource(textRes),
        style = MaterialTheme.typography.labelLarge,
        color = LocalFinancePalette.current.textDim,
        modifier = Modifier.padding(start = 4.dp, top = 8.dp).semantics { heading() },
    )
}

@Composable
private fun CategoryRow(category: FinanceCategory, onEdit: () -> Unit) {
    FinanceCard {
        ListItem(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(role = Role.Button, onClick = onEdit),
            leadingContent = {
                CategoryIcon(
                    token = category.iconToken,
                    tint = categoryColor(category.colorToken),
                )
            },
            headlineContent = { Text(category.name) },
            supportingContent = {
                Text(
                    text = stringResource(
                        if (category.type == TransactionType.EXPENSE) R.string.filter_expense else R.string.filter_income,
                    ),
                )
            },
        )
    }
}

@Composable
private fun EmptyCategoriesState(onAdd: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 56.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = stringResource(R.string.empty_categories_title),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            text = stringResource(R.string.empty_categories_message),
            color = LocalFinancePalette.current.textMid,
        )
        Button(onClick = onAdd) { Text(stringResource(R.string.add_category)) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CategoryEditorSheet(
    category: FinanceCategory?,
    existingCategories: List<FinanceCategory>,
    onDismiss: () -> Unit,
    onSaveNew: (NewCategory) -> Unit,
    onSaveExisting: (FinanceCategory) -> Unit,
    onDelete: () -> Unit,
) {
    var name by remember(category) { mutableStateOf(category?.name.orEmpty()) }
    var type by remember(category) { mutableStateOf(category?.type ?: TransactionType.EXPENSE) }
    var colorToken by remember(category) { mutableStateOf(category?.colorToken ?: "categoryIndigo") }
    var iconToken by remember(category) { mutableStateOf(category?.iconToken ?: "creditcard.fill") }
    val trimmedName = name.trim()
    val nameError = categoryNameError(
        name = trimmedName,
        type = type,
        categoryId = category?.id,
        categories = existingCategories,
        showBlankError = category != null,
    )
    val canSave = trimmedName.isNotEmpty() && nameError == null

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 720.dp)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = stringResource(if (category == null) R.string.new_category else R.string.edit_category),
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.semantics { heading() },
            )
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.category_name)) },
                supportingText = {
                    categoryNameErrorText(nameError)?.let { error ->
                        Text(stringResource(error), color = MaterialTheme.colorScheme.error)
                    }
                },
                isError = nameError != null,
                singleLine = true,
            )
            if (category == null) {
                CategoryTypePicker(selected = type, onSelected = { type = it })
            }
            CategoryColorPicker(selected = colorToken, onSelected = { colorToken = it })
            CategoryIconPicker(selected = iconToken, onSelected = { iconToken = it })
            Row(
                modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (category != null) {
                    TextButton(onClick = onDelete) {
                        Text(
                            text = stringResource(R.string.delete_category),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    Spacer(Modifier.weight(1f))
                }
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = {
                        if (category == null) {
                            onSaveNew(
                                NewCategory(
                                    name = trimmedName,
                                    iconToken = iconToken,
                                    type = type,
                                    colorToken = colorToken,
                                ),
                            )
                        } else {
                            onSaveExisting(
                                category.copy(
                                    name = trimmedName,
                                    iconToken = iconToken,
                                    colorToken = colorToken,
                                ),
                            )
                        }
                    },
                    enabled = canSave,
                ) {
                    Text(stringResource(if (category == null) R.string.add_category else R.string.save))
                }
            }
        }
    }
}

@Composable
private fun CategoryTypePicker(selected: TransactionType, onSelected: (TransactionType) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = stringResource(R.string.category_type), style = MaterialTheme.typography.labelLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = selected == TransactionType.EXPENSE,
                onClick = { onSelected(TransactionType.EXPENSE) },
                label = { Text(stringResource(R.string.filter_expense)) },
            )
            FilterChip(
                selected = selected == TransactionType.INCOME,
                onClick = { onSelected(TransactionType.INCOME) },
                label = { Text(stringResource(R.string.filter_income)) },
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CategoryColorPicker(selected: String, onSelected: (String) -> Unit) {
    val tokens = listOf(
        "categoryIndigo" to R.string.category_color_indigo,
        "categoryGreen" to R.string.category_color_green,
        "categoryAmber" to R.string.category_color_amber,
        "categoryPink" to R.string.category_color_pink,
        "categoryTeal" to R.string.category_color_teal,
        "categoryPurple" to R.string.category_color_purple,
    )
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = stringResource(R.string.category_color), style = MaterialTheme.typography.labelLarge)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            tokens.forEach { (token, label) ->
                FilterChip(
                    selected = selected == token,
                    onClick = { onSelected(token) },
                    label = { Text(stringResource(label)) },
                    leadingIcon = {
                        androidx.compose.foundation.layout.Box(
                            modifier = Modifier
                                .size(12.dp)
                                .background(categoryColor(token), CircleShape),
                        )
                    },
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CategoryIconPicker(selected: String, onSelected: (String) -> Unit) {
    val tokens = listOf(
        "creditcard.fill",
        "cart",
        "fork.knife",
        "cup.and.saucer",
        "house",
        "briefcase",
        "banknote",
        "gift",
        "airplane",
        "car",
        "star.circle",
        "ellipsis.circle",
    )
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = stringResource(R.string.category_icon), style = MaterialTheme.typography.labelLarge)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            tokens.forEach { token ->
                AssistChip(
                    onClick = { onSelected(token) },
                    label = { Icon(categoryIcon(token), contentDescription = stringResource(R.string.category_icon_option, token)) },
                    leadingIcon = null,
                    colors = androidx.compose.material3.AssistChipDefaults.assistChipColors(
                        containerColor = if (selected == token) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
                        labelColor = if (selected == token) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
                    ),
                )
            }
        }
    }
}

@Composable
private fun DeleteCategoryDialog(category: FinanceCategory, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.delete_category_confirmation_title)) },
        text = { Text(stringResource(R.string.delete_category_confirmation_message, category.name)) },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(stringResource(R.string.delete_category), color = MaterialTheme.colorScheme.error)
            }
        },
    )
}

private fun categoryNameError(
    name: String,
    type: TransactionType,
    categoryId: String?,
    categories: List<FinanceCategory>,
    showBlankError: Boolean,
): CategoryNameError? = when {
    name.isEmpty() && showBlankError -> CategoryNameError.BLANK
    !CategoryNameValidator.isValid(name) -> CategoryNameError.INVALID
    CategoryNameValidator.isDuplicate(
        name,
        categories.asSequence().filter { it.id != categoryId && it.type == type }.map(FinanceCategory::name),
    ) -> CategoryNameError.DUPLICATE
    else -> null
}

private fun categoryNameErrorText(error: CategoryNameError?): Int? = when (error) {
    CategoryNameError.BLANK -> R.string.category_name_blank
    CategoryNameError.INVALID -> R.string.category_name_invalid
    CategoryNameError.DUPLICATE -> R.string.category_name_duplicate
    null -> null
}

private enum class CategoryNameError { BLANK, INVALID, DUPLICATE }

@Composable
private fun categoryColor(token: String) = when (token) {
    "categoryGreen", "categoryTeal" -> MaterialTheme.colorScheme.secondary
    "categoryAmber" -> MaterialTheme.colorScheme.tertiary
    "categoryGray" -> MaterialTheme.colorScheme.outline
    "categoryPink", "categoryPurple", "categoryIndigo" -> MaterialTheme.colorScheme.primary
    else -> MaterialTheme.colorScheme.primary
}

private fun categoryIcon(token: String): ImageVector = when {
    token.contains("cart") -> Icons.Outlined.ShoppingCart
    token.contains("fork") || token.contains("cup") || token.contains("takeout") -> Icons.Outlined.Restaurant
    token.contains("house") -> Icons.Outlined.Home
    token.contains("briefcase") -> Icons.Outlined.BusinessCenter
    token.contains("banknote") -> Icons.Outlined.AccountBalanceWallet
    token.contains("chart") -> Icons.AutoMirrored.Outlined.ShowChart
    token.contains("gift") -> Icons.Outlined.CardGiftcard
    token.contains("airplane") -> Icons.Outlined.Flight
    token.contains("fuel") -> Icons.Outlined.LocalGasStation
    token.contains("wrench") -> Icons.Outlined.Build
    token.contains("bus") -> Icons.Outlined.DirectionsBus
    token.contains("taxi") -> Icons.Outlined.LocalTaxi
    token.contains("car") -> Icons.Outlined.DirectionsCar
    token.contains("star") -> Icons.Outlined.Star
    token.contains("trophy") -> Icons.Outlined.EmojiEvents
    token.contains("bolt") -> Icons.Outlined.Build
    token.contains("iphone") -> Icons.Outlined.PhoneIphone
    token.contains("globe") -> Icons.Outlined.Public
    token.contains("tv") -> Icons.Outlined.Tv
    token.contains("tshirt") -> Icons.Outlined.Checkroom
    token.contains("bag") -> Icons.Outlined.ShoppingBag
    token.contains("gamecontroller") -> Icons.Outlined.SportsEsports
    token.contains("book") -> Icons.AutoMirrored.Outlined.MenuBook
    token.contains("cross") || token.contains("pills") || token.contains("dumbbell") -> Icons.Outlined.LocalHospital
    token.contains("film") -> Icons.Outlined.Movie
    token.contains("music") -> Icons.Outlined.MusicNote
    token.contains("graduationcap") -> Icons.Outlined.School
    token.contains("pawprint") -> Icons.Outlined.Pets
    token.contains("arrow.uturn") -> Icons.AutoMirrored.Outlined.Undo
    token.contains("creditcard") -> Icons.Outlined.CreditCard
    token.contains("ellipsis") -> Icons.Outlined.MoreHoriz
    token.contains("dining") -> Icons.Outlined.LocalDining
    token.contains("work") -> Icons.Outlined.Work
    else -> Icons.Outlined.Category
}

@Composable
private fun CategoryIcon(token: String, tint: androidx.compose.ui.graphics.Color) {
    Icon(
        imageVector = categoryIcon(token),
        contentDescription = null,
        tint = tint,
    )
}
