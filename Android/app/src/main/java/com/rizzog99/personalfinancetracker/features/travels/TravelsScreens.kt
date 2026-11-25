package com.rizzog99.personalfinancetracker.features.travels

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.travel.FinanceTravel
import com.rizzog99.personalfinancetracker.domain.travel.TRAVEL_NAME_LIMIT
import com.rizzog99.personalfinancetracker.domain.travel.TRAVEL_SYMBOLS
import com.rizzog99.personalfinancetracker.domain.travel.TravelReport
import com.rizzog99.personalfinancetracker.domain.travel.TravelSummary
import com.rizzog99.personalfinancetracker.features.activity.TransactionEditorSheet
import com.rizzog99.personalfinancetracker.features.categories.categoryColor
import com.rizzog99.personalfinancetracker.ui.components.EmptyState
import com.rizzog99.personalfinancetracker.ui.components.ErrorState
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.components.LoadingState
import com.rizzog99.personalfinancetracker.ui.components.categoryDisplayName
import com.rizzog99.personalfinancetracker.ui.components.categoryIconFor
import com.rizzog99.personalfinancetracker.ui.components.coverWhenObscured
import com.rizzog99.personalfinancetracker.ui.components.travelIcon
import com.rizzog99.personalfinancetracker.ui.components.travelIconLabel
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatSignedCurrency
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinanceExtendedColors
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.launch

/** What the transaction editor needs to offer "Part of a trip?" (#284). */
class TravelChoice(
    val travels: List<FinanceTravel>,
    /** Preselected travel: the detail page's Add expense. */
    val presetId: String? = null,
    /** Creates a travel and answers its id, or null when the write failed (already reported). */
    val onCreate: suspend (name: String, symbolName: String) -> String?,
)

private fun shortDay(instant: Instant): String =
    instant.atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("d MMM", Locale.getDefault()))

private fun longDay(date: LocalDate): String = date.format(DateTimeFormatter.ofPattern("d MMM yyyy", Locale.getDefault()))

/** "3 expenses · 12 Sep – 16 Sep", or just the count for a one-day or empty trip (iOS `TravelRowView.subtitle`). */
@Composable
fun travelSubtitle(summary: TravelSummary): String {
    val count = pluralStringResource(R.plurals.travel_expenses, summary.count, summary.count)
    val start = summary.start ?: return count
    val end = summary.end ?: return count
    val from = shortDay(start)
    val to = shortDay(end)
    return if (from == to) count else "$count · $from – $to"
}

@Composable
private fun signedTotalColor(total: BigDecimal) = when {
    total.signum() == 0 -> MaterialTheme.colorScheme.onSurfaceVariant
    total > BigDecimal.ZERO -> LocalFinanceExtendedColors.current.positive
    else -> LocalFinanceExtendedColors.current.negative
}

/** An empty travel is neither income nor spending: no sign, neutral colour (iOS `TravelRowView`). */
private fun signedTotal(total: BigDecimal) =
    if (total.signum() == 0) formatCurrency(total, "EUR") else formatSignedCurrency(total, "EUR")

@Composable
private fun TravelTile(symbolName: String) {
    Box(
        modifier = Modifier.size(40.dp).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), RoundedCornerShape(12.dp)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(travelIcon(symbolName), contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
    }
}

/**
 * A collapsed travel: same shape as a transaction row, plus a chevron because it opens a page, not
 * the editor (iOS `TravelRowView`). One merged target described as "name, subtitle".
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TravelRow(summary: TravelSummary, onClick: () -> Unit, modifier: Modifier = Modifier, onLongClick: (() -> Unit)? = null) {
    val subtitle = travelSubtitle(summary)
    val hint = stringResource(R.string.travel_open_hint)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .combinedClickable(role = Role.Button, onClickLabel = hint, onClick = onClick, onLongClick = onLongClick)
            .semantics { contentDescription = "${summary.name}, $subtitle" }
            .padding(vertical = 12.dp, horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        TravelTile(summary.symbolName)
        // At large text the total moves under the subtitle, like Activity's own rows: side by side, a
        // narrow pane broke the name letter by letter.
        val largeText = LocalDensity.current.fontScale >= 1.3f
        Column(modifier = Modifier.weight(1f)) {
            Text(summary.name, style = MaterialTheme.typography.bodyLarge)
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (largeText) Text(signedTotal(summary.total), style = MaterialTheme.typography.titleMedium, color = signedTotalColor(summary.total))
        }
        if (!largeText) Text(signedTotal(summary.total), style = MaterialTheme.typography.titleMedium, color = signedTotalColor(summary.total))
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** The travel a row belongs to, on its category line (iOS `TransactionItemView`): icon and name, read as "In travel X". */
@Composable
fun TravelBadge(travel: FinanceTravel, modifier: Modifier = Modifier) {
    val description = stringResource(R.string.in_travel, travel.name)
    Row(
        modifier = modifier.clearAndSetSemantics { contentDescription = description },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(travelIcon(travel.symbolName), contentDescription = null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(travel.name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** iOS `TravelFormSheet`: a name of at most 24 characters and one of 8 icons. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun TravelFormSheet(
    onDismiss: () -> Unit,
    onSave: (name: String, symbolName: String) -> Unit,
    initialName: String = "",
    initialSymbol: String = TRAVEL_SYMBOLS.first(),
    isEditing: Boolean = false,
) {
    var name by rememberSaveable { mutableStateOf(initialName) }
    var symbol by rememberSaveable { mutableStateOf(initialSymbol) }
    val valid = name.isNotBlank()
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            modifier = Modifier.fillMaxWidth().coverWhenObscured().padding(start = 24.dp, end = 24.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(if (isEditing) R.string.edit_travel else R.string.new_travel),
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
            }
            OutlinedTextField(
                value = name,
                onValueChange = { name = it.take(TRAVEL_NAME_LIMIT) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.travel_name)) },
                singleLine = true,
            )
            Text(stringResource(R.string.travel_icon), style = MaterialTheme.typography.titleSmall)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                TRAVEL_SYMBOLS.forEach { choice ->
                    val selected = choice == symbol
                    Box(
                        modifier = Modifier
                            .size(48.dp)
                            .background(
                                if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh,
                                RoundedCornerShape(12.dp),
                            )
                            .selectable(selected = selected, role = Role.RadioButton, onClick = { symbol = choice }),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            travelIcon(choice),
                            contentDescription = stringResource(travelIconLabel(choice)),
                            tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            Button(onClick = { onSave(name.trim(), symbol) }, enabled = valid, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.save))
            }
        }
    }
}

/** "Part of a trip?" in the transaction editor (iOS `TransactionFormView.swift:270-305, 624-653`). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TravelSection(choice: TravelChoice, selectedId: String?, onSelect: (String?) -> Unit) {
    var creating by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.part_of_a_trip), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            IconButton(onClick = { creating = true }) {
                Icon(Icons.Outlined.Add, contentDescription = stringResource(R.string.add_travel))
            }
        }
        if (choice.travels.isEmpty()) {
            // A picker whose only option is None explains nothing; say what the feature is for.
            Text(stringResource(R.string.no_travels_message), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = selectedId == null, onClick = { onSelect(null) }, label = { Text(stringResource(R.string.travel_none)) })
                choice.travels.forEach { travel ->
                    FilterChip(
                        selected = selectedId == travel.id,
                        onClick = { onSelect(travel.id) },
                        label = { Text(travel.name) },
                        leadingIcon = { Icon(travelIcon(travel.symbolName), contentDescription = null, modifier = Modifier.size(18.dp)) },
                    )
                }
            }
        }
    }
    if (creating) {
        TravelFormSheet(
            onDismiss = { creating = false },
            onSave = { name, symbol ->
                creating = false
                scope.launch { choice.onCreate(name, symbol)?.let(onSelect) }
            },
        )
    }
}

/**
 * The selection's Travel action (iOS `TravelsView` in `.movingSelection`), as a sheet inside Activity
 * so the selection survives (D-09). Picking only reports the choice; Activity runs the write (D-11).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MoveToTravelSheet(
    summaries: List<TravelSummary>,
    showRemove: Boolean,
    onPick: (String?) -> Unit,
    onCreate: (name: String, symbolName: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var creating by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        // Scrolls: many travels, or large text, would otherwise push the last ones and Remove out of reach.
        Column(modifier = Modifier.fillMaxWidth().coverWhenObscured().verticalScroll(rememberScrollState()).padding(bottom = 16.dp)) {
            Row(modifier = Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
                Text(
                    stringResource(R.string.move_to_travel),
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                IconButton(onClick = { creating = true }) { Icon(Icons.Outlined.Add, contentDescription = stringResource(R.string.add_travel)) }
            }
            if (summaries.isEmpty()) {
                EmptyState(
                    title = stringResource(R.string.no_travels_title),
                    message = stringResource(R.string.no_travels_message),
                    action = { Button(onClick = { creating = true }) { Text(stringResource(R.string.add_travel)) } },
                )
            } else {
                summaries.forEach { summary -> TravelRow(summary, onClick = { onPick(summary.id) }) }
            }
            if (showRemove) {
                TextButton(onClick = { onPick(null) }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
                    Text(stringResource(R.string.remove_from_travel), color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
    if (creating) {
        TravelFormSheet(
            onDismiss = { creating = false },
            onSave = { name, symbol ->
                creating = false
                onCreate(name, symbol)
            },
        )
    }
}

@Composable
private fun travelsViewModel(): TravelsViewModel {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    return viewModel(
        factory = TravelsViewModel.factory(application.transactionRepository, application.travelRepository, application.categoryRepository),
    )
}

@Composable
private fun DeleteTravelDialog(name: String, count: Int, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        modifier = Modifier.coverWhenObscured(),
        title = { Text(stringResource(R.string.delete_travel_title, name)) },
        // The folder is destructive, its contents are not: the message has to say so.
        text = { Text(pluralStringResource(R.plurals.delete_travel_message, count, count)) },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
        confirmButton = { TextButton(onClick = onConfirm) { Text(stringResource(R.string.delete_travel)) } },
    )
}

/** iOS `TravelsView` in browse mode, as a full-screen page (D-07). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TravelsScreen(onBack: () -> Unit, onOpenTravel: (String) -> Unit) {
    val viewModel = travelsViewModel()
    val state by viewModel.uiState.collectAsState()
    val error by viewModel.error.collectAsState()
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    var adding by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<TravelSummary?>(null) }
    ErrorSnackbar(error, snackbar, viewModel::clearError)
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.travels_title)) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.back)) } },
                actions = { IconButton(onClick = { adding = true }) { Icon(Icons.Outlined.Add, contentDescription = stringResource(R.string.add_travel)) } },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        when {
            state.isLoading -> LoadingState(modifier = Modifier.padding(padding))
            state.isError -> ErrorState(message = stringResource(R.string.error_state_message), onRetry = viewModel::retry, modifier = Modifier.padding(padding))
            state.summaries.isEmpty() -> EmptyState(
                title = stringResource(R.string.no_travels_title),
                message = stringResource(R.string.no_travels_message),
                modifier = Modifier.padding(padding),
                action = { Button(onClick = { adding = true }) { Text(stringResource(R.string.add_travel)) } },
            )
            else -> LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                items(state.summaries, key = { it.id }) { summary ->
                    SwipeToDeleteTravel(summary, onDelete = { deleting = summary }) {
                        TravelRow(summary, onClick = { onOpenTravel(summary.id) })
                    }
                }
            }
        }
    }
    if (adding) {
        TravelFormSheet(onDismiss = { adding = false }, onSave = { name, symbol -> adding = false; scope.launch { viewModel.add(name, symbol) } })
    }
    deleting?.let { summary ->
        DeleteTravelDialog(summary.name, summary.count, onDismiss = { deleting = null }) {
            deleting = null
            scope.launch { viewModel.delete(summary.id) }
        }
    }
}

/** Swipe left asks first, like Activity's rows; the row springs back until the dialog is answered. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToDeleteTravel(summary: TravelSummary, onDelete: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) onDelete()
            false
        },
    )
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(
                modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.errorContainer).padding(horizontal = 20.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.delete_travel), tint = MaterialTheme.colorScheme.onErrorContainer)
            }
        },
    ) { content() }
}

@Composable
private fun ErrorSnackbar(error: Int?, host: SnackbarHostState, onShown: () -> Unit) {
    val message = error?.let { stringResource(it) }
    LaunchedEffect(message) {
        if (message != null) {
            host.showSnackbar(message)
            onShown()
        }
    }
}

/** iOS `TravelDetailSheet`, as a full-screen page (D-07). */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun TravelDetailScreen(travelId: String, onBack: () -> Unit, onAddExpense: (String) -> Unit) {
    val viewModel = travelsViewModel()
    val state by viewModel.uiState.collectAsState()
    val error by viewModel.error.collectAsState()
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val travel = state.travels.firstOrNull { it.id == travelId }
    val summary = state.summaries.firstOrNull { it.id == travelId }
    val members = state.members(travelId)
    val report = remember(members) { TravelReport.of(members, ZoneId.systemDefault()) }
    var menuOpen by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<FinanceTransaction?>(null) }
    // A failed member save is reported above the editor: the page's snackbar is hidden under the sheet.
    var saveFailed by remember { mutableStateOf(false) }
    ErrorSnackbar(error, snackbar, viewModel::clearError)
    // Deleted (here or elsewhere): nothing left to show. The one place that leaves, and only once:
    // the page stays composed through the exit transition, where a second Back would pop the list too.
    // Only a travel this page has shown can disappear: a just-opened page never bounces back on a
    // momentary "not there yet".
    var left by remember { mutableStateOf(false) }
    var shown by remember { mutableStateOf(false) }
    if (travel != null) shown = true
    LaunchedEffect(state.isLoading, travel) {
        if (shown && !left && !state.isLoading && !state.isError && travel == null) {
            left = true
            onBack()
        }
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(travel?.name.orEmpty(), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.back)) } },
                actions = {
                    IconButton(onClick = { menuOpen = true }) { Icon(Icons.Outlined.MoreVert, contentDescription = stringResource(R.string.travel_options)) }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.rename)) }, onClick = { menuOpen = false; renaming = true })
                        DropdownMenuItem(text = { Text(stringResource(R.string.delete_travel)) }, onClick = { menuOpen = false; deleting = true })
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        when {
            state.isLoading -> LoadingState(modifier = Modifier.padding(padding))
            state.isError -> ErrorState(message = stringResource(R.string.error_state_message), onRetry = viewModel::retry, modifier = Modifier.padding(padding))
            travel == null || summary == null -> Unit
            else -> Column(
                modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                FinanceCard {
                    Column(modifier = Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(stringResource(R.string.travel_total), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(signedTotal(summary.total), style = MaterialTheme.typography.headlineMedium, color = signedTotalColor(summary.total))
                        Text(pluralStringResource(R.plurals.travel_expenses, report.count, report.count), style = MaterialTheme.typography.bodyMedium)
                    }
                }
                if (report.count > 0) {
                    FinanceCard {
                        Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            val start = report.start
                            val end = report.end
                            if (start != null && end != null) {
                                StatRow(stringResource(R.string.travel_dates), if (start == end) longDay(start) else "${longDay(start)} – ${longDay(end)}")
                            }
                            StatRow(stringResource(R.string.travel_duration), pluralStringResource(R.plurals.travel_days, report.dayCount, report.dayCount))
                            StatRow(stringResource(R.string.travel_per_day), formatCurrency(report.perDay, "EUR"))
                            // Only worth a row when something was paid back.
                            if (report.refunded.signum() > 0) StatRow(stringResource(R.string.travel_refunded), formatCurrency(report.refunded, "EUR"))
                        }
                    }
                    Text(stringResource(R.string.travel_where_it_went), style = MaterialTheme.typography.titleSmall, modifier = Modifier.semantics { heading() })
                    FinanceCard {
                        Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            report.categories.forEach { (label, amount) ->
                                CategoryBar(label, amount, report.spent, state)
                            }
                        }
                    }
                }
                Button(onClick = { onAddExpense(travelId) }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Outlined.Add, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.travel_add_expense))
                }
                if (members.isEmpty()) {
                    EmptyState(title = stringResource(R.string.travel_no_expenses), message = stringResource(R.string.travel_no_expenses_message))
                } else {
                    Text(stringResource(R.string.travel_expenses_heading), style = MaterialTheme.typography.titleSmall, modifier = Modifier.semantics { heading() })
                    members.forEach { member ->
                        MemberRow(member, onOpen = { editing = member }, onRemove = { scope.launch { viewModel.removeFromTravel(member) } })
                    }
                }
            }
        }
    }
    if (renaming && travel != null) {
        TravelFormSheet(
            onDismiss = { renaming = false },
            onSave = { name, symbol -> renaming = false; scope.launch { viewModel.rename(travel.id, name, symbol) } },
            initialName = travel.name,
            initialSymbol = travel.symbolName,
            isEditing = true,
        )
    }
    if (deleting && travel != null) {
        DeleteTravelDialog(travel.name, members.size, onDismiss = { deleting = false }) {
            deleting = false
            scope.launch { viewModel.delete(travel.id) }
        }
    }
    editing?.let { member ->
        // ponytail: a plain single-row save; a recurring member is edited as "this transaction only".
        // Route through Activity's recurring dialog if a this-and-future edit from here is ever needed.
        TransactionEditorSheet(
            editingTransaction = member,
            categories = state.categories,
            receiptMappingRepository = application.receiptMappingRepository,
            onDismiss = { editing = null },
            // The editor stays open, draft and all, until the save holds: a failure keeps it for a retry.
            onSave = { transaction, _, _ -> scope.launch { if (viewModel.save(transaction)) editing = null else saveFailed = true } },
            travelChoice = TravelChoice(state.travels, onCreate = viewModel::add),
        )
    }
    if (saveFailed) {
        AlertDialog(
            onDismissRequest = { saveFailed = false },
            modifier = Modifier.coverWhenObscured(),
            text = { Text(stringResource(R.string.activity_update_failed)) },
            confirmButton = { TextButton(onClick = { saveFailed = false }) { Text(stringResource(R.string.dismiss)) } },
        )
    }
}

@Composable
private fun StatRow(label: String, value: String) {
    // The label keeps its width; a long value (a date span at large text) wraps, right-aligned.
    Row(modifier = Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(end = 16.dp))
        Text(value, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
    }
}

/** A bar per category: a ranking, readable at large text; the share is also its state for TalkBack. */
@Composable
private fun CategoryBar(label: String, amount: BigDecimal, spent: BigDecimal, state: TravelsUiState) {
    val share = if (spent.signum() > 0) amount.divide(spent, 4, RoundingMode.HALF_EVEN).toFloat() else 0f
    val percent = "${(share * 100).let { kotlin.math.round(it).toInt() }}%"
    val category = state.categories.firstOrNull { it.name == label }
    val color = categoryColor(category?.colorToken ?: "categoryGray")
    Column(modifier = Modifier.semantics(mergeDescendants = true) { stateDescription = percent }) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(categoryIconFor(category?.iconToken ?: ""), contentDescription = null, tint = color, modifier = Modifier.size(16.dp))
            Text(categoryDisplayName(label), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Text(formatCurrency(amount, "EUR"), style = MaterialTheme.typography.bodyMedium)
        }
        Spacer(Modifier.height(4.dp))
        LinearProgressIndicator(progress = { share }, modifier = Modifier.fillMaxWidth(), color = color)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MemberRow(member: FinanceTransaction, onOpen: () -> Unit, onRemove: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(role = Role.Button, onClick = onOpen, onLongClick = { menu = true })
                .padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(member.note.ifBlank { categoryDisplayName(member.categoryLabel) }, style = MaterialTheme.typography.bodyLarge)
                Text(
                    "${categoryDisplayName(member.categoryLabel)} · ${shortDay(member.timestamp)}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                formatSignedCurrency(member.amount, member.currencyCode),
                style = MaterialTheme.typography.titleMedium,
                color = signedTotalColor(member.amount),
            )
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.remove_from_travel)) }, onClick = { menu = false; onRemove() })
        }
    }
}
