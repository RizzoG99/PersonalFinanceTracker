package com.rizzog99.personalfinancetracker.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.DocumentScanner
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinancePalette

/** Consistent top-level controls for every main tab; feature content starts below this bar. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainTopBar(
    onOpenSettings: () -> Unit,
    onAddTransaction: () -> Unit,
    onScanReceipt: () -> Unit,
) {
    TopAppBar(
        title = {},
        navigationIcon = {
            IconButton(onClick = onOpenSettings) {
                Icon(Icons.Outlined.Settings, stringResource(R.string.settings_title))
            }
        },
        actions = {
            IconButton(onClick = onScanReceipt) {
                Icon(Icons.Outlined.DocumentScanner, stringResource(R.string.scan_receipt))
            }
            FilledIconButton(onClick = onAddTransaction) {
                Icon(
                    imageVector = Icons.Outlined.Add,
                    contentDescription = stringResource(R.string.add_transaction),
                )
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = Color.Transparent,
            navigationIconContentColor = LocalFinancePalette.current.textMid,
            actionIconContentColor = LocalFinancePalette.current.textMid,
        ),
    )
}
