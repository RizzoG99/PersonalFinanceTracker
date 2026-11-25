package com.rizzog99.personalfinancetracker.features.activity

import androidx.activity.compose.BackHandler
import androidx.annotation.PluralsRes
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Deselect
import androidx.compose.material.icons.outlined.Euro
import androidx.compose.material.icons.outlined.Flight
import androidx.compose.material.icons.outlined.SelectAll
import androidx.compose.material.icons.outlined.Sell
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalAccessibilityManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.ui.components.ReleaseTextFocusWhileObscured
import com.rizzog99.personalfinancetracker.ui.components.coverWhenObscured
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.rizzog99.personalfinancetracker.domain.travel.travelSummaries
import com.rizzog99.personalfinancetracker.features.travels.MoveToTravelSheet
import java.time.ZoneId

/**
 * The one pending bulk Undo (#285).
 *
 * Frozen iOS commits a pending mutation before arming a new one (`TransactionListViewModel.swift:524-531`).
 * A bulk Undo restores whole rows, so a stale one tapped after a later change would overwrite that
 * change. Cancelling its job removes the snackbar whether it is showing or still queued behind
 * another one, so [drop] runs before every Activity mutation and a dropped Undo is final.
 */
internal class BulkUndoSlot(private val scope: CoroutineScope) {
    private var job: Job? = null

    fun drop() {
        job?.cancel()
        job = null
    }

    fun launch(block: suspend CoroutineScope.() -> Unit) {
        drop()
        job = scope.launch(block = block)
    }
}

@Composable
internal fun rememberBulkUndoSlot(): BulkUndoSlot {
    val scope = rememberCoroutineScope()
    return remember(scope) { BulkUndoSlot(scope) }
}

internal enum class BulkSheet { Category, Amount, Description, Travel }

/**
 * Everything selection mode needs besides its two bars: Back leaves it, the shell hears about it
 * (it hides the bottom navigation and the +, D-04), and the action sheets run the bulk writes with
 * their 5 s Undo.
 */
@Composable
internal fun BulkSelectionEffects(
    state: ActivityUiState,
    viewModel: ActivityViewModel,
    snackbarHostState: SnackbarHostState,
    undoSlot: BulkUndoSlot,
    sheet: BulkSheet?,
    onSheetChange: (BulkSheet?) -> Unit,
    onSelectionModeChange: (Boolean) -> Unit,
    application: PersonalFinanceApplication,
) {
    val selecting = state.checkedIds != null
    val count = state.checkedIds?.size ?: 0
    val accessibilityManager = LocalAccessibilityManager.current
    val reportSelectionMode by rememberUpdatedState(onSelectionModeChange)
    // The screen's scope, not the sheet's: a Move write must outlive the sheet it was picked in (D-11).
    val scope = rememberCoroutineScope()

    BackHandler(enabled = selecting) { viewModel.exitSelection() }
    LaunchedEffect(selecting) { reportSelectionMode(selecting) }
    DisposableEffect(Unit) { onDispose { reportSelectionMode(false) } }

    /** Travel moves (#284): no Undo, as on iOS, but they still end any pending bulk Undo, which would put the old tag back. */
    fun move(write: suspend (Set<String>) -> Boolean) {
        val ids = state.checkedIds.orEmpty()
        onSheetChange(null)
        viewModel.exitSelection()
        undoSlot.drop()
        if (ids.isNotEmpty()) scope.launch { withContext(NonCancellable) { write(ids) } }
    }

    fun run(@PluralsRes message: Int, action: suspend () -> ActivityViewModel.BulkResult?) {
        onSheetChange(null)
        undoSlot.launch {
            // Never cut a write in half: a later mutation may cancel this job at any moment.
            val result = withContext(NonCancellable) { action() } ?: return@launch
            showUndo(
                snackbarHostState = snackbarHostState,
                message = application.resources.getQuantityString(message, result.count, result.count),
                application = application,
                accessibilityManager = accessibilityManager,
                onUndo = { withContext(NonCancellable) { viewModel.restore(result.prior) } },
            )
        }
    }

    when (sheet) {
        BulkSheet.Category -> BulkCategoryPicker(
            categories = state.categories,
            onDismiss = { onSheetChange(null) },
            onSelected = { category -> run(R.plurals.transactions_updated) { viewModel.bulkSetCategory(category) } },
        )
        BulkSheet.Amount -> BulkTextSheet(
            title = R.string.bulk_new_amount,
            count = count,
            keyboardType = KeyboardType.Decimal,
            prefix = "€",
            isValid = ::isValidBulkAmount,
            onDismiss = { onSheetChange(null) },
            onSet = { text ->
                parseBulkAmount(text)?.let { amount -> run(R.plurals.transactions_updated) { viewModel.bulkSetAmount(amount) } }
            },
        )
        BulkSheet.Description -> BulkTextSheet(
            title = R.string.bulk_description,
            count = count,
            keyboardType = KeyboardType.Text,
            prefix = null,
            isValid = { true },
            onDismiss = { onSheetChange(null) },
            onSet = { text -> run(R.plurals.transactions_updated) { viewModel.bulkSetNote(text) } },
        )
        BulkSheet.Travel -> MoveToTravelSheet(
            summaries = travelSummaries(state.allTransactions, state.travels, ZoneId.systemDefault()),
            showRemove = state.selectionHasTravel,
            onPick = { travelId -> move { ids -> viewModel.bulkSetTravel(ids, travelId) } },
            onCreate = { name, symbol -> move { ids -> viewModel.addTravelAndAssign(ids, name, symbol) } },
            onDismiss = { onSheetChange(null) },
        )
        null -> Unit
    }

    // A sheet left open after selection mode ended (Back) has no target.
    LaunchedEffect(selecting, sheet) { if (!selecting && sheet != null) onSheetChange(null) }
}

/**
 * Deletes the selection with its Undo. No confirmation, as on iOS: Undo is the safety net.
 * Separate from the sheets because it needs no input.
 */
internal fun runBulkDelete(
    viewModel: ActivityViewModel,
    snackbarHostState: SnackbarHostState,
    undoSlot: BulkUndoSlot,
    application: PersonalFinanceApplication,
    accessibilityManager: androidx.compose.ui.platform.AccessibilityManager?,
) {
    undoSlot.launch {
        val result = withContext(NonCancellable) { viewModel.bulkDelete() } ?: return@launch
        showUndo(
            snackbarHostState = snackbarHostState,
            message = application.resources.getQuantityString(R.plurals.transactions_deleted, result.count, result.count),
            application = application,
            accessibilityManager = accessibilityManager,
            onUndo = { withContext(NonCancellable) { viewModel.restore(result.prior) } },
        )
    }
}

/** Contextual top bar while selecting: Cancel, "N selected" (announced), Select All / Deselect All. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SelectionTopBar(state: ActivityUiState, onCancel: () -> Unit, onSelectAll: () -> Unit, onDeselectAll: () -> Unit) {
    val checked = state.checkedIds.orEmpty()
    val allVisibleChecked = state.visibleTransactions.isNotEmpty() && state.visibleTransactions.all { it.id in checked }
    TopAppBar(
        navigationIcon = {
            IconButton(onClick = onCancel) {
                Icon(Icons.Outlined.Close, contentDescription = stringResource(R.string.cancel))
            }
        },
        title = {
            Text(
                text = pluralStringResource(R.plurals.selection_count, checked.size, checked.size),
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            )
        },
        // An icon, not iOS's text button (D-13): at 200 % in Italian "Seleziona tutto" left the count
        // no room. The label is still what TalkBack reads.
        actions = {
            IconButton(onClick = if (allVisibleChecked) onDeselectAll else onSelectAll) {
                Icon(
                    imageVector = if (allVisibleChecked) Icons.Outlined.Deselect else Icons.Outlined.SelectAll,
                    contentDescription = stringResource(if (allVisibleChecked) R.string.deselect_all else R.string.select_all),
                )
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
    )
}

/** iOS's floating action bar (`ActivityView.swift:176-195`), Travel included (#284). */
@Composable
internal fun SelectionActionBar(enabled: Boolean, onDelete: () -> Unit, onSheet: (BulkSheet) -> Unit) {
    // Five across fit only at normal sizes: at large text a word like "Descrizione" would break
    // mid-word, so the actions go three and two, the longest labels on the row of two.
    val twoRows = LocalDensity.current.fontScale >= 1.3f
    val primary = MaterialTheme.colorScheme.primary
    Surface(color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.fillMaxWidth().testTag(BULK_ACTION_BAR_TAG)) {
        // Its own navigation-bar inset: on compact this bar stands in for the shell's NavigationBar,
        // which pads itself the same way under edge-to-edge (`MainActivity`).
        Column(modifier = Modifier.windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 4.dp, vertical = 4.dp)) {
            val first: @Composable RowScope.() -> Unit = {
                BulkActionButton(Icons.Outlined.Delete, R.string.bulk_delete, enabled, MaterialTheme.colorScheme.error, onDelete)
                BulkActionButton(Icons.Outlined.Sell, R.string.bulk_category, enabled, primary) { onSheet(BulkSheet.Category) }
                BulkActionButton(Icons.Outlined.Flight, R.string.bulk_travel, enabled, primary) { onSheet(BulkSheet.Travel) }
            }
            val second: @Composable RowScope.() -> Unit = {
                BulkActionButton(Icons.Outlined.Euro, R.string.bulk_amount, enabled, primary) { onSheet(BulkSheet.Amount) }
                BulkActionButton(Icons.AutoMirrored.Outlined.Notes, R.string.bulk_description, enabled, primary) {
                    onSheet(BulkSheet.Description)
                }
            }
            if (twoRows) {
                Row(content = first)
                Row(content = second)
            } else {
                Row {
                    first()
                    second()
                }
            }
        }
    }
}

@Composable
private fun RowScope.BulkActionButton(icon: ImageVector, @StringRes label: Int, enabled: Boolean, tint: Color, onClick: () -> Unit) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.weight(1f),
        colors = ButtonDefaults.textButtonColors(contentColor = tint),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, contentDescription = null)
            Text(stringResource(label), style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center)
        }
    }
}

/** Amount and Description: iOS's `AmountBulkEditSheet` / `DescriptionBulkEditSheet` (`ActivityView.swift:261-339`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BulkTextSheet(
    @StringRes title: Int,
    count: Int,
    keyboardType: KeyboardType,
    prefix: String?,
    isValid: (String) -> Boolean,
    onDismiss: () -> Unit,
    onSet: (String) -> Unit,
) {
    var text by rememberSaveable { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        ReleaseTextFocusWhileObscured()
        Column(
            modifier = Modifier.fillMaxWidth().coverWhenObscured().padding(start = 24.dp, end = 24.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = stringResource(title),
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
            }
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth().focusRequester(focus).testTag(BULK_INPUT_TAG),
                label = { Text(stringResource(title)) },
                prefix = prefix?.let { { Text(it) } },
                singleLine = keyboardType != KeyboardType.Text,
                keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
                supportingText = { Text(pluralStringResource(R.plurals.bulk_applies_to, count, count)) },
            )
            Button(onClick = { onSet(text) }, enabled = isValid(text), modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.bulk_set))
            }
        }
    }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
}
