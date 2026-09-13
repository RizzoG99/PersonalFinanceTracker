package com.rizzog99.personalfinancetracker.features.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.LocalFireDepartment
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.TaskAlt
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.pulse.FinancialPulseMetrics
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard

@Composable
fun FinancialPulseCard(
    metrics: FinancialPulseMetrics,
    dailyReminderEnabled: Boolean,
    pulsePromptDismissed: Boolean,
    onSetDailyReminder: () -> Unit,
    onDismissPrompt: () -> Unit,
    modifier: Modifier = Modifier,
) {
    FinanceCard(modifier = modifier) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Title row
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(
                    imageVector = Icons.Outlined.CheckCircle,
                    contentDescription = null,
                    modifier = Modifier.padding(end = 8.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Text(
                    text = stringResource(R.string.financial_pulse_title),
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
            }

            // Status text
            Text(
                text = if (metrics.todayTransactionCount > 0) {
                    stringResource(R.string.financial_pulse_complete)
                } else {
                    stringResource(R.string.financial_pulse_incomplete)
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Transaction count row
            PulseStatRow(
                icon = { Icon(Icons.Outlined.TaskAlt, contentDescription = null) },
                label = pluralStringResource(
                    id = R.plurals.financial_pulse_transactions,
                    count = metrics.todayTransactionCount,
                    metrics.todayTransactionCount,
                ),
            )

            // Streak row
            PulseStatRow(
                icon = { Icon(Icons.Outlined.LocalFireDepartment, contentDescription = null) },
                label = pluralStringResource(
                    id = R.plurals.financial_pulse_streak,
                    count = metrics.streakDays,
                    metrics.streakDays,
                ),
            )

            // Daily reminder prompt (only if not enabled and not dismissed)
            if (!dailyReminderEnabled && !pulsePromptDismissed) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.NotificationsActive,
                        contentDescription = null,
                        modifier = Modifier.padding(end = 0.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Text(
                        text = stringResource(R.string.daily_reminder_prompt),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = onSetDailyReminder) {
                        Text(stringResource(R.string.daily_reminder_set))
                    }
                    IconButton(onClick = onDismissPrompt, modifier = Modifier.padding(end = 0.dp)) {
                        Icon(Icons.Outlined.Close, contentDescription = stringResource(R.string.dismiss))
                    }
                }
            }
        }
    }
}

@Composable
private fun PulseStatRow(
    icon: @Composable () -> Unit,
    label: String,
    modifier: Modifier = Modifier,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = modifier.fillMaxWidth(),
    ) {
        icon()
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
