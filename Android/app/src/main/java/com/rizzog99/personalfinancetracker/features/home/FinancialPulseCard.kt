package com.rizzog99.personalfinancetracker.features.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.LocalFireDepartment
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.TaskAlt
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinanceExtendedColors

@Composable
fun FinancialPulseCard(
    metrics: FinancialPulseMetrics,
    dailyReminderEnabled: Boolean,
    pulsePromptDismissed: Boolean,
    onSetDailyReminder: () -> Unit,
    onDismissPrompt: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val complete = metrics.todayTransactionCount > 0
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
                // Matches the design doc's markup exactly: a 40dp circle (var(--pos-c) / mint),
                // holding a single 24dp check_circle glyph tinted var(--pos) (dark green). The
                // glyph's checkmark is a cutout in its own fill path, so the mint background shows
                // through it — that's what gives the nested-circle look, not a second icon layer.
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .background(
                            if (complete) LocalFinanceExtendedColors.current.positiveContainer else MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                            CircleShape,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = if (complete) Icons.Filled.CheckCircle else Icons.Outlined.CheckCircle,
                        contentDescription = null,
                        modifier = Modifier.size(24.dp),
                        tint = if (complete) LocalFinanceExtendedColors.current.positive else MaterialTheme.colorScheme.primary,
                    )
                }
                Text(
                    text = stringResource(R.string.financial_pulse_title),
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f).padding(start = 12.dp).semantics { heading() },
                )
            }

            // Status text
            Text(
                text = if (complete) {
                    stringResource(R.string.financial_pulse_complete)
                } else {
                    stringResource(R.string.financial_pulse_incomplete)
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Stat chips, side by side like the transaction-count/streak pair in the design.
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                PulseStatChip(
                    icon = {
                        Icon(
                            Icons.Outlined.TaskAlt,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    },
                    label = pluralStringResource(
                        id = R.plurals.financial_pulse_transactions,
                        count = metrics.todayTransactionCount,
                        metrics.todayTransactionCount,
                    ),
                    modifier = Modifier.weight(1f),
                )
                PulseStatChip(
                    icon = {
                        Icon(
                            Icons.Outlined.LocalFireDepartment,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    },
                    label = pluralStringResource(
                        id = R.plurals.financial_pulse_streak,
                        count = metrics.streakDays,
                        metrics.streakDays,
                    ),
                    modifier = Modifier.weight(1f),
                )
            }

            // Daily reminder prompt (only if not enabled and not dismissed)
            if (!dailyReminderEnabled && !pulsePromptDismissed) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.NotificationsActive,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = stringResource(R.string.daily_reminder_prompt),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                    FilledTonalButton(onClick = onSetDailyReminder) {
                        Text(stringResource(R.string.daily_reminder_set))
                    }
                    IconButton(onClick = onDismissPrompt, modifier = Modifier.padding(end = 0.dp)) {
                        Icon(
                            Icons.Outlined.Close,
                            contentDescription = stringResource(R.string.dismiss),
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PulseStatChip(
    icon: @Composable () -> Unit,
    label: String,
    modifier: Modifier = Modifier,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = modifier
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, RoundedCornerShape(16.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
    ) {
        icon()
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
