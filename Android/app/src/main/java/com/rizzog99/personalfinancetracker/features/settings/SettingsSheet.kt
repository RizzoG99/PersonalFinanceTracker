package com.rizzog99.personalfinancetracker.features.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinanceExtendedColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheet(
    onDismiss: () -> Unit,
    onOpenCategories: () -> Unit,
    onOpenBudgets: () -> Unit,
    onOpenDataTransfer: () -> Unit,
) {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val viewModel: SettingsViewModel = viewModel(
        factory = SettingsViewModel.factory(application.preferencesRepository),
    )
    val state by viewModel.uiState.collectAsState()
    var dayMenuExpanded by remember { mutableStateOf(false) }
    val endDay = if (state.payCycleStartDay > 1) state.payCycleStartDay - 1 else 28

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.settings_title),
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) }
            }

            Text(
                text = stringResource(R.string.pay_cycle),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.outline,
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
        }
    }
}
