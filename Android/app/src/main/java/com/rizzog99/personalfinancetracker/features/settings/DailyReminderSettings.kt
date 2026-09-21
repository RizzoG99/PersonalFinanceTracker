package com.rizzog99.personalfinancetracker.features.settings

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.text.format.DateFormat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimeInput
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.core.content.ContextCompat
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import java.time.LocalTime
import java.util.Calendar

/**
 * The reminder switch and its time, mirroring frozen iOS `ProfileReminderSection`: the time only
 * appears once the reminder is on, and changing it reschedules immediately.
 */
@Composable
fun DailyReminderSection(application: PersonalFinanceApplication) {
    val context = LocalContext.current
    val enabled by application.preferencesRepository.dailyReminderEnabled.collectAsState(initial = false)
    val time by application.preferencesRepository.dailyReminderTime.collectAsState(initial = null)
    val setEnabled = rememberDailyReminderEnabler(application)
    var picking by remember { mutableStateOf(false) }

    ListItem(
        leadingContent = { Icon(Icons.Outlined.Notifications, contentDescription = null) },
        headlineContent = { Text(stringResource(R.string.daily_reminder)) },
        supportingContent = { Text(stringResource(R.string.daily_reminder_detail)) },
        trailingContent = {
            Switch(checked = enabled, onCheckedChange = setEnabled)
        },
    )
    val reminderTime = time
    if (enabled && reminderTime != null) {
        val formatted = formatTimeOfDay(context, reminderTime)
        val description = stringResource(R.string.reminder_time_description, formatted)
        ListItem(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(role = Role.Button) { picking = true }
                .semantics { contentDescription = description },
            headlineContent = { Text(stringResource(R.string.reminder_time)) },
            trailingContent = {
                Text(
                    text = formatted,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            },
        )
        if (picking) {
            ReminderTimePickerDialog(
                initial = reminderTime,
                onDismiss = { picking = false },
                onConfirm = {
                    picking = false
                    application.setDailyReminderTime(it)
                },
            )
        }
    }
}

/**
 * The one way to turn the reminder on or off from the UI. POST_NOTIFICATIONS is a runtime
 * permission from API 33; without it WorkManager would run a worker that can never post anything,
 * so the permission is asked for before the preference is written.
 */
@Composable
fun rememberDailyReminderEnabler(application: PersonalFinanceApplication): (Boolean) -> Unit {
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> if (granted) application.setDailyReminderEnabled(true) }

    return { enabled ->
        when {
            !enabled -> application.setDailyReminderEnabled(false)
            Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(
                application,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED -> launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
            else -> application.setDailyReminderEnabled(true)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReminderTimePickerDialog(
    initial: LocalTime,
    onDismiss: () -> Unit,
    onConfirm: (LocalTime) -> Unit,
) {
    val state = rememberTimePickerState(
        initialHour = initial.hour,
        initialMinute = initial.minute,
        is24Hour = DateFormat.is24HourFormat(LocalContext.current),
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.reminder_time)) },
        text = {
            // The default period selector paints the chosen AM/PM on `tertiaryContainer`, which
            // in this theme is the green that means income everywhere else. Selection is
            // `primary` in this app.
            val colors = TimePickerDefaults.colors(
                periodSelectorSelectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                periodSelectorSelectedContentColor = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            // The dial's radius does not grow with the font scale, so at large text its 24-hour
            // inner and outer rings collide. Type the time in instead.
            if (LocalDensity.current.fontScale > 1.3f) {
                TimeInput(state = state, colors = colors)
            } else {
                TimePicker(state = state, colors = colors)
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(LocalTime.of(state.hour, state.minute)) }) {
                Text(stringResource(R.string.save))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

/**
 * Locale- and system-aware: [DateFormat.getTimeFormat] follows both the context's locale and the
 * device's 24-hour setting, which a hardcoded `HH:mm` would not.
 */
internal fun formatTimeOfDay(context: Context, time: LocalTime): String {
    val calendar = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, time.hour)
        set(Calendar.MINUTE, time.minute)
    }
    return DateFormat.getTimeFormat(context).format(calendar.time)
}
