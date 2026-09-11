package com.rizzog99.personalfinancetracker.features.insights

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Equalizer
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.DocumentScanner
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.goal.FinanceGoal
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.money.AmountInput
import com.rizzog99.personalfinancetracker.ui.components.AppBackground
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.components.MainTopBar
import com.rizzog99.personalfinancetracker.ui.components.SheetDragHandle
import com.rizzog99.personalfinancetracker.ui.components.categoryIconFor
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatPeriod
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinancePalette
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InsightsScreen(onAddTransaction: () -> Unit, onOpenSettings: () -> Unit) {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val viewModel: InsightsViewModel = viewModel(
        factory = InsightsViewModel.factory(
            application.transactionRepository,
            application.goalRepository,
            application.preferencesRepository,
        ),
    )
    val state by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var creatingGoal by remember { mutableStateOf(false) }
    var editingGoal by remember { mutableStateOf<FinanceGoal?>(null) }
    var selectedGoal by remember { mutableStateOf<GoalProgress?>(null) }
    var deletingGoal by remember { mutableStateOf<FinanceGoal?>(null) }

    Scaffold(
        topBar = {
            MainTopBar(
                onOpenSettings = onOpenSettings,
                onAddTransaction = onAddTransaction,
                onScanReceipt = onAddTransaction,
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = Color.Transparent,
    ) { padding ->
        InsightsContent(
            state = state,
            onAddGoal = { creatingGoal = true },
            onSelectGoal = { selectedGoal = it },
            modifier = Modifier.padding(padding),
        )
    }

    if (creatingGoal) {
        GoalEditorSheet(
            goal = null,
            onDismiss = { creatingGoal = false },
            onSave = { newGoal ->
                viewModel.addGoal(newGoal) { saved ->
                    if (saved) creatingGoal = false else scope.launch {
                        snackbarHostState.showSnackbar(application.getString(R.string.goal_save_error))
                    }
                }
            },
        )
    }
    editingGoal?.let { goal ->
        GoalEditorSheet(
            goal = goal,
            onDismiss = { editingGoal = null },
            onSave = { newGoal ->
                viewModel.updateGoal(
                    goal.copy(
                        name = newGoal.name,
                        targetAmount = newGoal.targetAmount,
                        deadline = newGoal.deadline,
                        colorToken = newGoal.colorToken,
                        iconToken = newGoal.iconToken,
                    ),
                ) { saved ->
                    if (saved) editingGoal = null else scope.launch {
                        snackbarHostState.showSnackbar(application.getString(R.string.goal_save_error))
                    }
                }
            },
        )
    }
    selectedGoal?.let { progress ->
        GoalDetailSheet(
            progress = progress,
            currencyCode = state.currencyCode,
            onDismiss = { selectedGoal = null },
            onEdit = {
                selectedGoal = null
                editingGoal = progress.goal
            },
            onDelete = {
                selectedGoal = null
                deletingGoal = progress.goal
            },
            onAddFunds = { amount, onFinished ->
                viewModel.addFunds(progress.goal, amount, state.currencyCode, onFinished)
            },
        )
    }
    deletingGoal?.let { goal ->
        DeleteGoalDialog(
            goal = goal,
            onDismiss = { deletingGoal = null },
            onConfirm = {
                viewModel.deleteGoal(goal) { deleted ->
                    deletingGoal = null
                    if (!deleted) scope.launch {
                        snackbarHostState.showSnackbar(application.getString(R.string.goal_save_error))
                    }
                }
            },
        )
    }
}

@Composable
private fun InsightsContent(
    state: InsightsUiState,
    onAddGoal: () -> Unit,
    onSelectGoal: (GoalProgress) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalFinancePalette.current
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 112.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Text(
                stringResource(R.string.insights_title),
                style = MaterialTheme.typography.displaySmall,
                modifier = Modifier.semantics { heading() },
            )
        }
        item {
            GoalsSection(
                goals = state.goals,
                currencyCode = state.currencyCode,
                onAddGoal = onAddGoal,
                onSelectGoal = onSelectGoal,
            )
        }
        item {
            PaceCard(state.paceInsight)
        }
        item {
            HealthSection(state.health)
        }
        item {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    stringResource(R.string.insights_spending),
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.semantics { heading() },
                )
                Text(stringResource(R.string.insights_spending_detail), color = palette.textMid)
            }
        }
        if (state.categorySpending.isEmpty()) {
            item {
                FinanceCard {
                    Text(
                        stringResource(R.string.insights_empty_spending),
                        modifier = Modifier.fillMaxWidth().padding(24.dp),
                        color = palette.textMid,
                    )
                }
            }
        } else {
            items(state.categorySpending.take(5), key = CategorySpending::label) { category ->
                FinanceCard {
                    Row(
                        Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(category.label, modifier = Modifier.weight(1f))
                        Text(formatCurrency(category.amount, state.currencyCode), color = palette.negative)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun GoalsSection(
    goals: List<GoalProgress>,
    currencyCode: String,
    onAddGoal: () -> Unit,
    onSelectGoal: (GoalProgress) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.goals_title),
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.semantics { heading() },
                )
                Text(stringResource(R.string.goals_subtitle), color = LocalFinancePalette.current.textMid)
            }
            IconButton(onClick = onAddGoal) {
                Icon(Icons.Outlined.Add, stringResource(R.string.add_goal))
            }
        }
        if (goals.isEmpty()) {
            FinanceCard {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp, horizontal = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        Icons.Outlined.Flag,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(32.dp),
                    )
                    Text(stringResource(R.string.set_first_goal), style = MaterialTheme.typography.titleLarge)
                    Text(
                        stringResource(R.string.goals_empty_message),
                        color = LocalFinancePalette.current.textMid,
                    )
                }
            }
        } else {
            goals.chunked(2).forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    row.forEach { progress ->
                        GoalCard(
                            progress = progress,
                            currencyCode = currencyCode,
                            modifier = Modifier.weight(1f),
                            onClick = { onSelectGoal(progress) },
                        )
                    }
                    if (row.size == 1) {
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun GoalCard(
    progress: GoalProgress,
    currencyCode: String,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val accent = goalColor(progress.goal.colorToken)
    val fraction = (progress.currentAmount / progress.goal.targetAmount)
        .coerceIn(BigDecimal.ZERO, BigDecimal.ONE)
        .toFloat()
    val daysLeft = progress.goal.deadline?.let {
        ChronoUnit.DAYS.between(LocalDate.now(), it.atZone(ZoneId.systemDefault()).toLocalDate()).coerceAtLeast(0)
    }
    FinanceCard(
        modifier = modifier
            .clickable(role = Role.Button, onClick = onClick),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(categoryIconFor(progress.goal.iconToken), null, tint = accent)
                Spacer(Modifier.weight(1f))
                daysLeft?.let {
                    Text(
                        stringResource(R.string.goal_days_left, it),
                        style = MaterialTheme.typography.labelSmall,
                        color = LocalFinancePalette.current.textDim,
                    )
                }
            }
            Text(progress.goal.name, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall)
            androidx.compose.material3.LinearProgressIndicator(
                progress = { fraction },
                modifier = Modifier.fillMaxWidth(),
                color = accent,
                trackColor = LocalFinancePalette.current.hairline,
            )
            Text(
                text = stringResource(
                    R.string.goal_progress,
                    formatCurrency(progress.currentAmount, currencyCode),
                    formatCurrency(progress.goal.targetAmount, currencyCode),
                ),
                style = MaterialTheme.typography.labelSmall,
                color = LocalFinancePalette.current.textMid,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun PaceCard(insight: PaceInsight) {
    val palette = LocalFinancePalette.current
    val (icon, title, detail, color) = when (insight.direction) {
        PaceDirection.UP -> listOf(Icons.Outlined.ArrowUpward, stringResource(R.string.pace_watch), stringResource(R.string.pace_watch_detail), palette.negative)
        PaceDirection.DOWN -> listOf(Icons.Outlined.ArrowDownward, stringResource(R.string.pace_under), stringResource(R.string.pace_under_detail), palette.positive)
        PaceDirection.FLAT -> listOf(Icons.Outlined.Equalizer, stringResource(R.string.pace_on_track), stringResource(R.string.pace_on_track_detail), MaterialTheme.colorScheme.primary)
        PaceDirection.BUILDING -> listOf(Icons.Outlined.Equalizer, stringResource(R.string.pace_building), stringResource(R.string.pace_building_detail), MaterialTheme.colorScheme.primary)
    }
    FinanceCard {
        Row(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Icon(icon as androidx.compose.ui.graphics.vector.ImageVector, null, tint = color as Color, modifier = Modifier.size(32.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(title as String, style = MaterialTheme.typography.titleLarge)
                Text(detail as String, color = palette.textMid)
            }
            insight.percent?.let { Text(stringResource(R.string.pace_percent, it), color = color, style = MaterialTheme.typography.titleMedium) }
        }
    }
}

@Composable
private fun HealthSection(health: FinancialHealth?) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.health_score), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
        Text(stringResource(R.string.health_score_detail), color = LocalFinancePalette.current.textMid)
        FinanceCard {
            if (health == null) {
                Text(stringResource(R.string.health_score_empty), modifier = Modifier.fillMaxWidth().padding(24.dp), color = LocalFinancePalette.current.textMid)
            } else {
                Row(Modifier.fillMaxWidth().padding(20.dp), horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("${health.score}", style = MaterialTheme.typography.displayMedium, color = MaterialTheme.colorScheme.primary, fontFamily = FontFamily.Monospace)
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(R.string.health_score_value, health.score), style = MaterialTheme.typography.titleLarge)
                        health.components.forEach { component ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(component.name, modifier = Modifier.weight(1f), color = LocalFinancePalette.current.textMid)
                                androidx.compose.material3.LinearProgressIndicator(
                                    progress = { component.score.toFloat() / component.max },
                                    modifier = Modifier.width(90.dp),
                                    color = MaterialTheme.colorScheme.primary,
                                    trackColor = LocalFinancePalette.current.hairline,
                                )
                                Text(" ${component.score}/${component.max}", style = MaterialTheme.typography.labelMedium)
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun GoalEditorSheet(goal: FinanceGoal?, onDismiss: () -> Unit, onSave: (NewGoal) -> Unit) {
    var name by remember(goal) { mutableStateOf(goal?.name.orEmpty()) }
    var amountText by remember(goal) { mutableStateOf(goal?.targetAmount?.toPlainString().orEmpty()) }
    var colorToken by remember(goal) { mutableStateOf(goal?.colorToken ?: "categoryIndigo") }
    var iconToken by remember(goal) { mutableStateOf(goal?.iconToken ?: "star.fill") }
    var hasDeadline by remember(goal) { mutableStateOf(goal?.deadline != null) }
    var deadline by remember(goal) { mutableStateOf(goal?.deadline ?: Instant.now().plus(180, ChronoUnit.DAYS)) }
    var choosingDeadline by remember { mutableStateOf(false) }
    var choosingIcon by remember { mutableStateOf(false) }
    val parsedAmount = AmountInput.parse(amountText)
    val canSave = name.trim().isNotEmpty() && parsedAmount != null && parsedAmount > BigDecimal.ZERO
    val sectionShape = RoundedCornerShape(28.dp)
    val sectionColor = MaterialTheme.colorScheme.surfaceVariant

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        dragHandle = null,
        containerColor = MaterialTheme.colorScheme.background,
    ) {
        AppBackground(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.96f)) {
            SheetDragHandle()
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(),
            ) {
            Box(
                modifier = Modifier.fillMaxWidth().padding(start = 12.dp, top = 28.dp, end = 12.dp, bottom = 8.dp),
            ) {
                Text(
                    text = stringResource(if (goal == null) R.string.new_goal else R.string.edit_goal),
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier
                        .align(Alignment.CenterStart)
                        .semantics { heading() },
                )
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Spacer(Modifier.weight(1f))
                    FilledIconButton(
                        onClick = {
                            onSave(
                                NewGoal(
                                    name = name,
                                    targetAmount = requireNotNull(parsedAmount),
                                    deadline = deadline.takeIf { hasDeadline },
                                    colorToken = colorToken,
                                    iconToken = iconToken,
                                ),
                            )
                        },
                        enabled = canSave,
                    ) {
                        Icon(Icons.Outlined.Check, stringResource(if (goal == null) R.string.add_goal else R.string.save))
                    }
                }
            }

                Column(
                    modifier = Modifier
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 24.dp, vertical = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                IconButton(
                    onClick = { choosingIcon = true },
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .size(80.dp)
                        .clip(sectionShape)
                        .background(goalColor(colorToken).copy(alpha = 0.15f))
                        .border(1.5.dp, goalColor(colorToken).copy(alpha = 0.4f), sectionShape),
                ) {
                    Icon(
                        imageVector = categoryIconFor(iconToken),
                        contentDescription = stringResource(R.string.choose_goal_icon),
                        tint = goalColor(colorToken),
                        modifier = Modifier.size(36.dp),
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.goal_details), style = MaterialTheme.typography.titleMedium)
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(sectionColor, sectionShape)
                            .padding(horizontal = 24.dp, vertical = 16.dp),
                    ) {
                        TextField(
                            value = name,
                            onValueChange = { name = it.take(24) },
                            modifier = Modifier.fillMaxWidth(),
                            placeholder = { Text(stringResource(R.string.goal_name)) },
                            singleLine = true,
                            colors = goalEditorTextFieldColors(),
                        )
                        HorizontalDivider(color = LocalFinancePalette.current.hairline)
                        Text(
                            text = "${name.length}/24",
                            style = MaterialTheme.typography.labelMedium,
                            color = if (name.length == 24) MaterialTheme.colorScheme.error else LocalFinancePalette.current.textDim,
                            modifier = Modifier.align(Alignment.End),
                        )
                    }
                }

                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.goal_target), style = MaterialTheme.typography.titleMedium)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(sectionColor, sectionShape)
                            .padding(start = 24.dp, end = 20.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(stringResource(R.string.amount), color = LocalFinancePalette.current.textMid)
                        TextField(
                            value = amountText,
                            onValueChange = { amountText = AmountInput.sanitize(it) },
                            modifier = Modifier.weight(1f),
                            placeholder = { Text(AmountInput.formattedDisplay(BigDecimal.ZERO).removeSuffix(" €")) },
                            singleLine = true,
                            textStyle = MaterialTheme.typography.bodyLarge.copy(
                                textAlign = TextAlign.End,
                                fontFamily = FontFamily.Monospace,
                            ),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done),
                            isError = amountText.isNotEmpty() && (parsedAmount == null || parsedAmount <= BigDecimal.ZERO),
                            colors = goalEditorTextFieldColors(),
                        )
                        Text(stringResource(R.string.currency_eur), color = LocalFinancePalette.current.textMid)
                    }
                    if (amountText.isNotEmpty() && (parsedAmount == null || parsedAmount <= BigDecimal.ZERO)) {
                        Text(stringResource(R.string.goal_target_error), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                }

                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.category_color), style = MaterialTheme.typography.titleMedium)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(sectionColor, sectionShape)
                            .padding(horizontal = 12.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        goalColorTokens().forEach { token ->
                            IconButton(
                                onClick = { colorToken = token },
                                modifier = Modifier
                                    .size(40.dp)
                                    .clip(CircleShape)
                                    .background(goalColor(token)),
                            ) {
                                if (colorToken == token) {
                                    Icon(Icons.Outlined.Check, goalColorLabel(token), tint = MaterialTheme.colorScheme.onPrimary)
                                }
                            }
                        }
                    }
                }

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(sectionColor, sectionShape)
                        .padding(horizontal = 24.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.set_deadline), modifier = Modifier.weight(1f))
                        Switch(checked = hasDeadline, onCheckedChange = { hasDeadline = it })
                    }
                    if (hasDeadline) {
                        TextButton(onClick = { choosingDeadline = true }) {
                            Text(stringResource(R.string.goal_deadline_value, formatGoalDate(deadline)))
                        }
                    }
                }
                }
            }
        }
    }
    if (choosingIcon) {
        AlertDialog(
            onDismissRequest = { choosingIcon = false },
            title = { Text(stringResource(R.string.choose_goal_icon)) },
            text = {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    goalIconTokens().forEach { token ->
                        IconButton(
                            onClick = {
                                iconToken = token
                                choosingIcon = false
                            },
                            modifier = Modifier
                                .size(48.dp)
                                .clip(RoundedCornerShape(14.dp))
                                .background(
                                    if (iconToken == token) goalColor(colorToken).copy(alpha = 0.15f) else MaterialTheme.colorScheme.surfaceVariant,
                                ),
                        ) {
                            Icon(categoryIconFor(token), stringResource(R.string.category_icon_option, token), tint = goalColor(colorToken))
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { choosingIcon = false }) { Text(stringResource(R.string.done)) } },
        )
    }
    if (choosingDeadline) {
        GoalDatePicker(
            initial = deadline,
            onDismiss = { choosingDeadline = false },
            onConfirm = {
                deadline = it
                choosingDeadline = false
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GoalDetailSheet(
    progress: GoalProgress,
    currencyCode: String,
    onDismiss: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onAddFunds: (BigDecimal, (Boolean) -> Unit) -> Unit,
) {
    var contribution by remember { mutableStateOf("") }
    var contributionFailed by remember { mutableStateOf(false) }
    val parsedContribution = AmountInput.parse(contribution)
    val accent = goalColor(progress.goal.colorToken)
    val fraction = (progress.currentAmount / progress.goal.targetAmount).coerceIn(BigDecimal.ZERO, BigDecimal.ONE).toFloat()
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(categoryIconFor(progress.goal.iconToken), null, tint = accent, modifier = Modifier.size(28.dp))
                Spacer(Modifier.width(12.dp))
                Text(progress.goal.name, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f).semantics { heading() })
                IconButton(onClick = onEdit) { Icon(Icons.Outlined.Edit, stringResource(R.string.edit_goal)) }
                IconButton(onClick = onDelete) { Icon(Icons.Outlined.Delete, stringResource(R.string.delete_goal)) }
            }
            Text(
                stringResource(
                    R.string.goal_progress,
                    formatCurrency(progress.currentAmount, currencyCode),
                    formatCurrency(progress.goal.targetAmount, currencyCode),
                ),
                color = LocalFinancePalette.current.textMid,
            )
            androidx.compose.material3.LinearProgressIndicator(
                progress = { fraction },
                modifier = Modifier.fillMaxWidth(),
                color = accent,
                trackColor = LocalFinancePalette.current.hairline,
            )
            OutlinedTextField(
                value = contribution,
                onValueChange = {
                    contribution = AmountInput.sanitize(it)
                    contributionFailed = false
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.add_funds)) },
                suffix = { Text(stringResource(R.string.currency_eur)) },
                isError = contributionFailed,
                supportingText = {
                    if (contributionFailed) Text(stringResource(R.string.goal_fund_error))
                },
                singleLine = true,
            )
            Button(
                onClick = {
                    onAddFunds(requireNotNull(parsedContribution)) { saved ->
                        if (saved) contribution = "" else contributionFailed = true
                    }
                },
                enabled = parsedContribution != null && parsedContribution > BigDecimal.ZERO,
                modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
            ) { Text(stringResource(R.string.add_funds)) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GoalDatePicker(initial: Instant, onDismiss: () -> Unit, onConfirm: (Instant) -> Unit) {
    val state = rememberDatePickerState(initialSelectedDateMillis = initial.toEpochMilli())
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = { state.selectedDateMillis?.let { onConfirm(Instant.ofEpochMilli(it)) } }) {
                Text(stringResource(R.string.save))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    ) { DatePicker(state = state) }
}

@Composable
private fun DeleteGoalDialog(goal: FinanceGoal, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.delete_goal_confirmation_title)) },
        text = { Text(stringResource(R.string.delete_goal_confirmation_message, goal.name)) },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(stringResource(R.string.delete_goal), color = MaterialTheme.colorScheme.error)
            }
        },
    )
}

@Composable
private fun goalColor(token: String): Color {
    val darkTheme = isSystemInDarkTheme()
    return when (token) {
        "categoryGreen" -> if (darkTheme) Color(0xFF22D3A0) else Color(0xFF0A6B4F)
        "categoryAmber" -> if (darkTheme) Color(0xFFF59E0B) else Color(0xFFB45309)
        "categoryPink" -> if (darkTheme) Color(0xFFEC4899) else Color(0xFFDB2777)
        "categoryPurple" -> if (darkTheme) Color(0xFF8B5CF6) else Color(0xFF7C3AED)
        "categoryTeal" -> if (darkTheme) Color(0xFF14B8A6) else Color(0xFF0E7490)
        "categoryGray" -> if (darkTheme) Color(0xFF94A3B8) else Color(0xFF64748B)
        else -> if (darkTheme) Color(0xFF6366F1) else Color(0xFF4F46E5)
    }
}

private fun goalColorTokens() = listOf("categoryIndigo", "categoryGreen", "categoryAmber", "categoryPink", "categoryPurple", "categoryTeal", "categoryGray")

@Composable
private fun goalColorLabel(token: String): String = stringResource(
    when (token) {
        "categoryGreen" -> R.string.category_color_green
        "categoryAmber" -> R.string.category_color_amber
        "categoryPink" -> R.string.category_color_pink
        "categoryTeal" -> R.string.category_color_teal
        "categoryPurple" -> R.string.category_color_purple
        "categoryGray" -> R.string.category_color_gray
        else -> R.string.category_color_indigo
    },
)

@Composable
private fun goalEditorTextFieldColors() = TextFieldDefaults.colors(
    focusedContainerColor = Color.Transparent,
    unfocusedContainerColor = Color.Transparent,
    disabledContainerColor = Color.Transparent,
    focusedIndicatorColor = Color.Transparent,
    unfocusedIndicatorColor = Color.Transparent,
    disabledIndicatorColor = Color.Transparent,
)

private fun goalIconTokens() = listOf("cross.circle.fill", "airplane", "house.fill", "gift.fill", "graduationcap.fill", "star.fill")

private fun formatGoalDate(instant: Instant): String = java.time.format.DateTimeFormatter
    .ofLocalizedDate(java.time.format.FormatStyle.MEDIUM)
    .withLocale(java.util.Locale.getDefault())
    .withZone(ZoneId.systemDefault())
    .format(instant)
