package com.rizzog99.personalfinancetracker.features.settings

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Fingerprint
import androidx.compose.material.icons.outlined.Pin
import androidx.compose.material.icons.outlined.Upload
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.clickable
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.security.PinCodec
import com.rizzog99.personalfinancetracker.features.security.PinSetupScreen
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.launch

private enum class SecurityFlow { SET_PIN, CHANGE_PIN }
private enum class DataConfirmation { RESTORE, DELETE_ALL }

/** Full-screen settings, matching the design (not a bottom sheet). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheet(
    onDismiss: () -> Unit,
    onOpenCategories: () -> Unit,
    onOpenScanCategories: () -> Unit,
    onOpenBudgets: () -> Unit,
    onOpenDataTransfer: () -> Unit,
) {
    val context = LocalContext.current
    val application = context.applicationContext as PersonalFinanceApplication
    val viewModel: SettingsViewModel = viewModel(
        factory = SettingsViewModel.factory(application.preferencesRepository),
    )
    val state by viewModel.uiState.collectAsState()
    var dayMenuExpanded by remember { mutableStateOf(false) }
    val endDay = if (state.payCycleStartDay > 1) state.payCycleStartDay - 1 else 28
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    val pinHash by application.preferencesRepository.pinHash.collectAsState(initial = null)
    val pinSalt by application.preferencesRepository.pinSalt.collectAsState(initial = null)
    val biometricEnabled by application.preferencesRepository.biometricEnabled.collectAsState(initial = false)
    val lastBackupAt by application.preferencesRepository.lastBackupAt.collectAsState(initial = null)

    var securityFlow by remember { mutableStateOf<SecurityFlow?>(null) }
    var confirming by remember { mutableStateOf<DataConfirmation?>(null) }
    var pendingRestoreUri by remember { mutableStateOf<android.net.Uri?>(null) }

    val backupFailedMessage = stringResource(R.string.backup_failed)
    val backupCompleteMessage = stringResource(R.string.backup_complete)
    val restoreFailedMessage = stringResource(R.string.restore_failed)
    val restoreCompleteMessage = stringResource(R.string.restore_complete)

    val createBackupDocument = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val result = runCatching {
                context.contentResolver.openOutputStream(uri)?.use { application.backupRepository.export(it) }
                    ?: error("Could not open file")
            }
            if (result.isSuccess) {
                application.preferencesRepository.setLastBackupAt(java.time.Instant.now())
                snackbarHostState.showSnackbar(backupCompleteMessage)
            } else {
                snackbarHostState.showSnackbar(backupFailedMessage)
            }
        }
    }
    val openRestoreDocument = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            pendingRestoreUri = uri
            confirming = DataConfirmation.RESTORE
        }
    }

    BackHandler(onBack = onDismiss)

    if (securityFlow != null) {
        PinSetupScreen(
            onCancel = { securityFlow = null },
            onPinCreated = { pin ->
                val salt = PinCodec.randomSalt()
                scope.launch {
                    application.preferencesRepository.setPin(PinCodec.hash(pin, salt), salt)
                    securityFlow = null
                }
            },
        )
        return
    }

    confirming?.let { confirmation ->
        AlertDialog(
            onDismissRequest = { confirming = null; pendingRestoreUri = null },
            title = {
                Text(
                    stringResource(
                        if (confirmation == DataConfirmation.RESTORE) R.string.restore_confirm_title else R.string.delete_all_data,
                    ),
                )
            },
            text = {
                Text(
                    stringResource(
                        if (confirmation == DataConfirmation.RESTORE) R.string.restore_confirm_message else R.string.delete_all_data_confirm_message,
                    ),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirming = null
                    when (confirmation) {
                        DataConfirmation.RESTORE -> {
                            val uri = pendingRestoreUri
                            pendingRestoreUri = null
                            if (uri != null) {
                                scope.launch {
                                    val result = runCatching {
                                        context.contentResolver.openInputStream(uri)?.use { application.backupRepository.import(it) }
                                            ?: error("Could not open file")
                                    }
                                    if (result.isSuccess) application.categoryRepository.seedDefaultsIfEmpty()
                                    snackbarHostState.showSnackbar(if (result.isSuccess) restoreCompleteMessage else restoreFailedMessage)
                                }
                            }
                        }
                        DataConfirmation.DELETE_ALL -> {
                            scope.launch {
                                application.database.clearAllTables()
                                application.categoryRepository.seedDefaultsIfEmpty()
                            }
                        }
                    }
                }) {
                    Text(
                        stringResource(if (confirmation == DataConfirmation.RESTORE) R.string.restore_from_backup else R.string.delete_all_data),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { confirming = null; pendingRestoreUri = null }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings_title)) },
                navigationIcon = {
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) { Snackbar(snackbarData = it) } },
        containerColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = stringResource(R.string.pay_cycle),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.outline,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                text = stringResource(R.string.pay_cycle_start_day, state.payCycleStartDay),
                style = MaterialTheme.typography.titleMedium,
            )
            Box {
                OutlinedButton(
                    onClick = { dayMenuExpanded = true },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(state.payCycleStartDay.toString())
                }
                DropdownMenu(
                    expanded = dayMenuExpanded,
                    onDismissRequest = { dayMenuExpanded = false },
                    modifier = Modifier.heightIn(max = 320.dp),
                ) {
                    (1..28).forEach { day ->
                        DropdownMenuItem(
                            text = { Text(day.toString()) },
                            onClick = {
                                viewModel.setPayCycleStartDay(day)
                                dayMenuExpanded = false
                            },
                        )
                    }
                }
            }
            Text(
                text = stringResource(R.string.pay_cycle_detail, state.payCycleStartDay, endDay),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            ListItem(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button, onClick = onOpenCategories),
                headlineContent = { Text(stringResource(R.string.categories)) },
                supportingContent = { Text(stringResource(R.string.categories_settings_detail)) },
                trailingContent = {
                    Icon(
                        imageVector = Icons.AutoMirrored.Outlined.ArrowForward,
                        contentDescription = null,
                    )
                },
            )
            ListItem(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button, onClick = onOpenScanCategories),
                headlineContent = { Text(stringResource(R.string.scan_categories_entry)) },
                supportingContent = { Text(stringResource(R.string.scan_categories_description)) },
                trailingContent = {
                    Icon(
                        imageVector = Icons.AutoMirrored.Outlined.ArrowForward,
                        contentDescription = null,
                    )
                },
            )
            ListItem(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button, onClick = onOpenBudgets),
                headlineContent = { Text(stringResource(R.string.budgets_title)) },
                supportingContent = { Text(stringResource(R.string.budgets_settings_detail)) },
                trailingContent = {
                    Icon(
                        imageVector = Icons.AutoMirrored.Outlined.ArrowForward,
                        contentDescription = null,
                    )
                },
            )

            Text(
                text = stringResource(R.string.data_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.outline,
                modifier = Modifier.semantics { heading() },
            )
            ListItem(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button, onClick = onOpenDataTransfer),
                headlineContent = { Text(stringResource(R.string.import_export_title)) },
                supportingContent = { Text(stringResource(R.string.import_export_settings_detail)) },
                trailingContent = {
                    Icon(
                        imageVector = Icons.AutoMirrored.Outlined.ArrowForward,
                        contentDescription = null,
                    )
                },
            )
            val backupSubtitle = lastBackupAt?.let {
                stringResource(
                    R.string.last_backed_up,
                    DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(it.atZone(java.time.ZoneId.systemDefault())),
                )
            } ?: stringResource(R.string.not_backed_up_detail)
            ListItem(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button) {
                        createBackupDocument.launch("personal-finance-backup.json")
                    },
                leadingContent = {
                    Icon(
                        imageVector = if (lastBackupAt == null) Icons.Outlined.CloudOff else Icons.Outlined.Upload,
                        contentDescription = null,
                    )
                },
                headlineContent = { Text(stringResource(R.string.back_up_now)) },
                supportingContent = { Text(backupSubtitle) },
            )
            ListItem(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button) {
                        openRestoreDocument.launch(arrayOf("application/json"))
                    },
                leadingContent = { Icon(Icons.Outlined.Download, contentDescription = null) },
                headlineContent = { Text(stringResource(R.string.restore_from_backup)) },
            )
            ListItem(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button) { confirming = DataConfirmation.DELETE_ALL },
                leadingContent = {
                    Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                },
                headlineContent = { Text(stringResource(R.string.delete_all_data), color = MaterialTheme.colorScheme.error) },
            )

            Text(
                text = stringResource(R.string.security_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.outline,
                modifier = Modifier.semantics { heading() },
            )
            ListItem(
                leadingContent = { Icon(Icons.Outlined.Fingerprint, contentDescription = null) },
                headlineContent = { Text(stringResource(R.string.biometric_unlock)) },
                trailingContent = {
                    Switch(
                        checked = biometricEnabled && pinHash != null,
                        enabled = pinHash != null,
                        onCheckedChange = { checked ->
                            scope.launch { application.preferencesRepository.setBiometricEnabled(checked) }
                        },
                    )
                },
            )
            ListItem(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button) {
                        securityFlow = if (pinHash == null) SecurityFlow.SET_PIN else SecurityFlow.CHANGE_PIN
                    },
                leadingContent = { Icon(Icons.Outlined.Pin, contentDescription = null) },
                headlineContent = { Text(stringResource(if (pinHash == null) R.string.set_pin else R.string.change_pin)) },
                supportingContent = { Text(stringResource(R.string.pin_enabled_detail)) },
                trailingContent = {
                    Icon(imageVector = Icons.AutoMirrored.Outlined.ArrowForward, contentDescription = null)
                },
            )
        }
    }
}
