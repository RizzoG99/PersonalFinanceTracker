package com.rizzog99.personalfinancetracker.features.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.dashboard.SafeToSpend
import com.rizzog99.personalfinancetracker.domain.dashboard.SafeToSpendCalculator
import com.rizzog99.personalfinancetracker.domain.dashboard.SafeToSpendStanding
import com.rizzog99.personalfinancetracker.domain.dashboard.safeToSpendStanding
import com.rizzog99.personalfinancetracker.domain.money.AmountInput
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatDayMonth
import com.rizzog99.personalfinancetracker.ui.formatters.formatSignedCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatWholeCurrency
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinanceExtendedColors
import java.math.BigDecimal
import java.time.LocalDate

const val SAFE_TO_SPEND_HERO_TAG = "safeToSpendHero"
const val SAFE_TO_SPEND_BREAKDOWN_TAG = "safeToSpendBreakdown"
const val SAFE_TO_SPEND_WHAT_IF_TAG = "safeToSpendWhatIf"

/** Shown for every masked per-day or breakdown figure, as iOS's "••••". */
private const val SHORT_MASK = "••••"

/**
 * Home's hero (#298, iOS `BalanceCardView` at b649dff plus #260 standing and #213 what-if on main):
 * what's safe to spend until payday, how it was worked out, and what a spend today would leave.
 */
@Composable
internal fun SafeToSpendCard(
    safe: SafeToSpend,
    today: LocalDate,
    bufferPercent: Int,
    currencyCode: String,
    hideAmounts: Boolean,
    hasTransactions: Boolean,
) {
    FinanceCard(containerColor = MaterialTheme.colorScheme.primaryContainer) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = stringResource(R.string.safe_to_spend),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.semantics { heading() },
            )
            if (safe.income.signum() == 0) {
                NoIncome(safe, hasTransactions)
            } else {
                SafeToSpendOutcome(
                    amount = safe.amount,
                    safe = safe,
                    today = today,
                    currencyCode = currencyCode,
                    hideAmounts = hideAmounts,
                    amountStyle = MaterialTheme.typography.displayMedium,
                    modifier = Modifier.testTag(SAFE_TO_SPEND_HERO_TAG),
                )
                Breakdown(safe, bufferPercent, currencyCode, hideAmounts)
                WhatIf(safe, today, currencyCode, hideAmounts)
            }
        }
    }
}

/**
 * No income this cycle. With spending already recorded the usual cause is a pay cycle that doesn't
 * start on salary day — say so instead of looking like an empty app.
 */
@Composable
private fun NoIncome(safe: SafeToSpend, hasTransactions: Boolean) {
    val start = formatDayMonth(safe.cycleStart)
    Text(
        text = when {
            safe.spent.signum() > 0 -> stringResource(R.string.safe_to_spend_no_income_spent, start)
            hasTransactions -> stringResource(R.string.safe_to_spend_no_income_history, start)
            else -> stringResource(R.string.safe_to_spend_no_income_empty)
        },
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onPrimaryContainer,
    )
}

/** The amount left and where it stands: the hero's figure, and what a what-if spend would leave. */
@Composable
private fun SafeToSpendOutcome(
    amount: BigDecimal,
    safe: SafeToSpend,
    today: LocalDate,
    currencyCode: String,
    hideAmounts: Boolean,
    amountStyle: TextStyle,
    modifier: Modifier = Modifier,
) {
    val standing = safeToSpendStanding(amount, safe.buffer)
    // Amber like a budget near its limit, red only once past the buffer — always with its own line.
    val statusColor: Color? = when (standing) {
        SafeToSpendStanding.WITHIN_PLAN -> null
        SafeToSpendStanding.USING_BUFFER -> LocalFinanceExtendedColors.current.categoryAmber
        SafeToSpendStanding.OVER_PLAN -> LocalFinanceExtendedColors.current.negative
    }
    val lastDay = formatDayMonth(SafeToSpendCalculator.lastDay(safe.payday))
    val perDay = SafeToSpendCalculator.perDay(amount, today, safe.payday)
        ?.let { if (hideAmounts) SHORT_MASK else formatWholeCurrency(it, currencyCode) }
    val line = when {
        standing == SafeToSpendStanding.OVER_PLAN -> stringResource(R.string.safe_to_spend_over_plan, lastDay)
        standing == SafeToSpendStanding.USING_BUFFER -> stringResource(R.string.safe_to_spend_using_buffer, lastDay)
        perDay != null -> stringResource(R.string.safe_to_spend_until_per_day, lastDay, perDay)
        else -> stringResource(R.string.safe_to_spend_until, lastDay)
    }
    val spokenLine = if (standing == SafeToSpendStanding.WITHIN_PLAN && perDay != null) {
        stringResource(R.string.safe_to_spend_until_per_day_a11y, lastDay, perDay)
    } else {
        line
    }
    Column(
        modifier = modifier.semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            // Fixed-width mask: the formatted amount's length would leak its magnitude.
            text = if (hideAmounts) stringResource(R.string.balance_hidden_placeholder) else formatCurrency(amount, currencyCode),
            style = amountStyle,
            // Bold as iOS (`.largeTitle.bold()`, `.title2.bold()`): it also makes the amount large
            // text, where amber and red clear 3:1 on the card in both themes (#298 D-09).
            fontWeight = FontWeight.Bold,
            color = statusColor ?: MaterialTheme.colorScheme.onPrimaryContainer,
        )
        Text(
            text = line,
            style = MaterialTheme.typography.bodyMedium,
            // The line says the standing in words; at body size amber/red fall under 4.5:1 here
            // (3.19–4.11), so it keeps the card's readable colour (D-09).
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.semantics { contentDescription = spokenLine },
        )
    }
}

/** A disclosure row: the whole line toggles, and TalkBack hears whether it is open. */
@Composable
private fun Disclosure(title: String, expanded: Boolean, onToggle: () -> Unit) {
    val state = stringResource(if (expanded) R.string.disclosure_expanded else R.string.disclosure_collapsed)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clickable(role = Role.Button, onClick = onToggle)
            .semantics { stateDescription = state },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary, modifier = Modifier.weight(1f))
        Icon(
            imageVector = if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
    }
}

@Composable
private fun Breakdown(safe: SafeToSpend, bufferPercent: Int, currencyCode: String, hideAmounts: Boolean) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    Column {
        Disclosure(stringResource(R.string.safe_to_spend_how), expanded) { expanded = !expanded }
        if (!expanded) return@Column
        Column(
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp).testTag(SAFE_TO_SPEND_BREAKDOWN_TAG),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            // Income and spending themselves sit on the cycle tiles below; here only what's left of them.
            BreakdownRow(stringResource(R.string.safe_to_spend_still_available), safe.income - safe.spent, currencyCode, hideAmounts, deducted = false)
            if (safe.recurring.signum() > 0) BreakdownRow(stringResource(R.string.safe_to_spend_recurring_due), safe.recurring, currencyCode, hideAmounts)
            if (safe.goals.signum() > 0) BreakdownRow(stringResource(R.string.safe_to_spend_goal_contributions), safe.goals, currencyCode, hideAmounts)
            BreakdownRow(stringResource(R.string.safe_to_spend_buffer_row, bufferPercent), safe.buffer, currencyCode, hideAmounts)
            Text(
                stringResource(R.string.safe_to_spend_buffer_explanation),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.75f),
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            BreakdownRow(stringResource(R.string.safe_to_spend), safe.amount, currencyCode, hideAmounts, deducted = false, emphasized = true)
        }
    }
}

/** Label and amount side by side; stacked at large font scale so long Italian labels fit. */
@Composable
private fun BreakdownRow(
    label: String,
    amount: BigDecimal,
    currencyCode: String,
    hideAmounts: Boolean,
    /** Taken out of the income: shown with a minus, as iOS's `-€x`. */
    deducted: Boolean = true,
    emphasized: Boolean = false,
) {
    val value = when {
        hideAmounts -> SHORT_MASK
        deducted -> formatSignedCurrency(amount.negate(), currencyCode)
        else -> formatCurrency(amount, currencyCode)
    }
    val style = MaterialTheme.typography.bodyMedium.copy(fontWeight = if (emphasized) FontWeight.SemiBold else FontWeight.Normal)
    val color = MaterialTheme.colorScheme.onPrimaryContainer
    val merged = Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}
    if (LocalDensity.current.fontScale >= 1.3f) {
        Column(merged, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, style = style, color = color)
            Text(value, style = style, color = color)
        }
    } else {
        Row(merged, verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = style, color = color, modifier = Modifier.weight(1f))
            Spacer(Modifier.width(12.dp))
            Text(value, style = style, color = color)
        }
    }
}

/**
 * "If I spend €X today, am I still within plan until payday?" (#213). Nothing is saved: the answer is
 * the hero's own figure minus X, read the same way. Empty or unreadable input shows nothing — it's a
 * question being typed, not a form to submit.
 */
@Composable
private fun WhatIf(safe: SafeToSpend, today: LocalDate, currencyCode: String, hideAmounts: Boolean) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    var text by rememberSaveable { mutableStateOf("") }
    Column {
        Disclosure(stringResource(R.string.what_if_title), expanded) { expanded = !expanded }
        if (!expanded) return@Column
        Column(
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp).testTag(SAFE_TO_SPEND_WHAT_IF_TAG),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = text,
                onValueChange = { text = AmountInput.sanitize(it) },
                label = { Text(stringResource(R.string.what_if_amount_label)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.fillMaxWidth(),
            )
            AmountInput.parse(text)?.takeIf { it.signum() > 0 }?.let { spend ->
                SafeToSpendOutcome(
                    amount = safe.amount - spend,
                    safe = safe,
                    today = today,
                    currencyCode = currencyCode,
                    hideAmounts = hideAmounts,
                    amountStyle = MaterialTheme.typography.titleLarge,
                )
            }
        }
    }
}
