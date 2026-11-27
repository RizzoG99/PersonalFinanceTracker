package com.rizzog99.personalfinancetracker.features.insights

import android.text.format.DateUtils
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowDropDown
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ChevronLeft
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DateRangePicker
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDateRangePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.insights.CategoryTrend
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerBar
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerGranularity
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerPeriod
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerType
import com.rizzog99.personalfinancetracker.domain.insights.TrendDirection
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerCalendar
import com.rizzog99.personalfinancetracker.domain.insights.customRangeBounds
import com.rizzog99.personalfinancetracker.features.categories.categoryColor
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.components.categoryDisplayName
import com.rizzog99.personalfinancetracker.ui.components.categoryIconFor
import com.rizzog99.personalfinancetracker.ui.components.coverWhenObscured
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinanceExtendedColors
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Formatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** The explorer's controls, as the screen wires them to [InsightsViewModel]. */
internal class ExplorerActions(
    val onPrevious: () -> Unit,
    val onNext: () -> Unit,
    val onGranularity: (ExplorerGranularity) -> Unit,
    val onCustomRange: (LocalDate, LocalDate) -> Unit,
    val onType: (ExplorerType) -> Unit,
    val onOpenCategory: (CategoryTrend) -> Unit,
)

/** "Sep 2026", "2026", or a day range — iOS `ExplorerPeriod.label`. */
@Composable
internal fun explorerPeriodLabel(period: ExplorerPeriod, zone: ZoneId): String {
    val context = LocalContext.current
    val locale = Locale.getDefault()
    return when (period.granularity) {
        ExplorerGranularity.MONTH -> DateTimeFormatter.ofPattern("LLL yyyy", locale).format(period.start.atZone(zone))
        ExplorerGranularity.YEAR -> DateTimeFormatter.ofPattern("yyyy", locale).format(period.start.atZone(zone))
        // The end is exclusive: show the last included day.
        ExplorerGranularity.WEEK, ExplorerGranularity.CUSTOM -> DateUtils.formatDateRange(
            context,
            Formatter(StringBuilder(), locale),
            period.start.toEpochMilli(),
            period.end.toEpochMilli() - 1,
            DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_SHOW_YEAR or DateUtils.FORMAT_ABBREV_MONTH,
            zone.id,
        ).toString()
    }
}

/** Insights' Breakdown explorer (#303), iOS `BreakdownExplorerSection` at b649dff. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BreakdownExplorerSection(state: InsightsUiState, actions: ExplorerActions) {
    val period = state.explorerPeriod ?: return
    val label = explorerPeriodLabel(period, state.zoneId)
    val isIncome = state.explorerType == ExplorerType.INCOME
    val breakdown = state.explorer
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                stringResource(R.string.explorer_breakdown),
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.semantics { heading() },
            )
            Text(stringResource(R.string.explorer_subtitle), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        FinanceCard {
            Column(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                ExplorerNavigator(state, label, actions)
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    listOf(ExplorerType.EXPENSES to R.string.explorer_expenses, ExplorerType.INCOME to R.string.explorer_income)
                        .forEachIndexed { index, (type, text) ->
                            SegmentedButton(
                                selected = state.explorerType == type,
                                onClick = { actions.onType(type) },
                                shape = SegmentedButtonDefaults.itemShape(index, 2),
                            ) { Text(stringResource(text), maxLines = 1, overflow = TextOverflow.Ellipsis) }
                        }
                }
                if (breakdown.trends.isEmpty()) {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            stringResource(if (isIncome) R.string.explorer_empty_income else R.string.explorer_empty_expenses, label),
                            style = MaterialTheme.typography.titleMedium,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.semantics { heading() },
                        )
                        Text(
                            stringResource(R.string.explorer_empty_hint),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                } else {
                    Text(
                        formatCurrency(breakdown.total, state.currencyCode),
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    ExplorerBarChart(breakdown.bars, breakdown.barsByMonth, state.currencyCode)
                    ExplorerDonut(breakdown.trends)
                }
            }
        }
        breakdown.trends.forEach { trend ->
            CategoryTrendRow(trend, isIncome, state.currencyCode) { actions.onOpenCategory(trend) }
        }
    }
}

@Composable
private fun ExplorerNavigator(state: InsightsUiState, label: String, actions: ExplorerActions) {
    val period = state.explorerPeriod ?: return
    var menuOpen by remember { mutableStateOf(false) }
    var pickingRange by rememberSaveable { mutableStateOf(false) }
    val hint = stringResource(R.string.explorer_period_hint)
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = actions.onPrevious, enabled = state.canGoPrevious) {
            Icon(Icons.Outlined.ChevronLeft, contentDescription = stringResource(R.string.explorer_previous))
        }
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
            TextButton(
                onClick = { menuOpen = true },
                modifier = Modifier.heightIn(min = 48.dp).semantics { onClick(label = hint) { menuOpen = true; true } },
            ) {
                Text(
                    label,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center,
                )
                Icon(Icons.Outlined.ArrowDropDown, contentDescription = null, tint = MaterialTheme.colorScheme.onSurface)
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }, modifier = Modifier.coverWhenObscured()) {
                listOf(
                    ExplorerGranularity.WEEK to R.string.explorer_week,
                    ExplorerGranularity.MONTH to R.string.explorer_month,
                    ExplorerGranularity.YEAR to R.string.explorer_year,
                ).forEach { (granularity, text) ->
                    DropdownMenuItem(
                        text = { Text(stringResource(text)) },
                        onClick = {
                            menuOpen = false
                            actions.onGranularity(granularity)
                        },
                        trailingIcon = { if (period.granularity == granularity) Icon(Icons.Outlined.Check, contentDescription = null) },
                        // TalkBack can't see the check icon.
                        modifier = Modifier.semantics { selected = period.granularity == granularity },
                    )
                }
                // An item, not a choice: re-picking it on a custom range reopens the picker to edit it.
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.explorer_custom_range_menu)) },
                    onClick = {
                        menuOpen = false
                        pickingRange = true
                    },
                    trailingIcon = {
                        Icon(
                            if (period.granularity == ExplorerGranularity.CUSTOM) Icons.Outlined.Check else Icons.Outlined.CalendarMonth,
                            contentDescription = null,
                        )
                    },
                )
            }
        }
        IconButton(onClick = actions.onNext, enabled = state.canGoNext) {
            Icon(Icons.Outlined.ChevronRight, contentDescription = stringResource(R.string.explorer_next))
        }
    }
    if (pickingRange) {
        ExplorerCustomRangeDialog(
            state = state,
            period = period,
            onDismiss = { pickingRange = false },
            onApply = { from, through ->
                pickingRange = false
                actions.onCustomRange(from, through)
            },
        )
    }
}

/** iOS `CustomRangeSheet`: whole days, from the first transaction's day (or today) through today. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ExplorerCustomRangeDialog(
    state: InsightsUiState,
    period: ExplorerPeriod,
    onDismiss: () -> Unit,
    onApply: (LocalDate, LocalDate) -> Unit,
) {
    val bounds = remember(period, state.firstTransaction, state.now) {
        customRangeBounds(state.firstTransaction, state.now, period, ExplorerCalendar.of(state.zoneId))
    }
    val earliest = bounds.earliest.utcMillis()
    val latest = bounds.latest.utcMillis()
    val pickerState = rememberDateRangePickerState(
        initialSelectedStartDateMillis = bounds.initialFrom.utcMillis(),
        initialSelectedEndDateMillis = bounds.initialTo.utcMillis(),
        yearRange = bounds.earliest.year..bounds.latest.year,
        selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis in earliest..latest
            override fun isSelectableYear(year: Int) = year in bounds.earliest.year..bounds.latest.year
        },
    )
    val start = pickerState.selectedStartDateMillis
    val end = pickerState.selectedEndDateMillis
    DatePickerDialog(
        onDismissRequest = onDismiss,
        modifier = Modifier.coverWhenObscured(),
        confirmButton = {
            TextButton(
                enabled = start != null,
                onClick = { onApply(start!!.utcDate(), (end ?: start).utcDate()) },
            ) { Text(stringResource(R.string.explorer_apply)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    ) {
        DateRangePicker(
            state = pickerState,
            // Without a weight the month list takes the whole dialog and pushes Cancel/Apply off-screen.
            modifier = Modifier.weight(1f),
            title = { Text(stringResource(R.string.explorer_custom_range), modifier = Modifier.padding(start = 24.dp, top = 16.dp)) },
            showModeToggle = false,
        )
    }
}

private fun LocalDate.utcMillis(): Long = atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
private fun Long.utcDate(): LocalDate = Instant.ofEpochMilli(this).atZone(ZoneOffset.UTC).toLocalDate()

private fun barLabel(bar: ExplorerBar, byMonth: Boolean, locale: Locale): String =
    if (byMonth) DateTimeFormatter.ofPattern("LLLL yyyy", locale).format(bar.day)
    else DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).format(bar.day)

private fun axisLabel(bar: ExplorerBar, byMonth: Boolean, locale: Locale): String =
    DateTimeFormatter.ofPattern(if (byMonth) "LLL" else "d MMM", locale).format(bar.day)

/**
 * One bar per day (per month for a year or a range over 62 days), drawn on a Canvas (D-03). Each
 * bar is its own TalkBack node, "date, amount", as each Swift Charts mark is on iOS.
 */
@Composable
private fun ExplorerBarChart(bars: List<ExplorerBar>, byMonth: Boolean, currencyCode: String) {
    if (bars.isEmpty()) return
    val locale = Locale.getDefault()
    val barColor = MaterialTheme.colorScheme.primary
    val gridColor = MaterialTheme.colorScheme.outlineVariant
    val max = bars.maxOf { it.amount }.toFloat().takeIf { it > 0f } ?: 1f
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        // Above the plot, not over it: at large text an overlaid label covered the tallest bar.
        Text(
            formatCurrency(bars.maxOf { it.amount }, currencyCode),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.align(Alignment.End).clearAndSetSemantics {},
        )
        Box(modifier = Modifier.fillMaxWidth().height(140.dp)) {
            Canvas(modifier = Modifier.fillMaxWidth().fillMaxHeight()) {
                val slot = size.width / bars.size
                val barWidth = (slot * 0.7f).coerceAtLeast(1f)
                drawLine(gridColor, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 1.dp.toPx())
                drawLine(gridColor, Offset(0f, 0f), Offset(size.width, 0f), strokeWidth = 1.dp.toPx())
                bars.forEachIndexed { index, bar ->
                    val height = bar.amount.toFloat() / max * size.height
                    if (height > 0f) {
                        drawRect(
                            color = barColor,
                            topLeft = Offset(index * slot + (slot - barWidth) / 2, size.height - height),
                            size = Size(barWidth, height),
                        )
                    }
                }
            }
            Row(modifier = Modifier.fillMaxWidth().fillMaxHeight()) {
                bars.forEach { bar ->
                    val description = "${barLabel(bar, byMonth, locale)}, ${formatCurrency(bar.amount, currencyCode)}"
                    Box(Modifier.weight(1f).fillMaxHeight().semantics { contentDescription = description })
                }
            }
        }
        Row(modifier = Modifier.fillMaxWidth().clearAndSetSemantics {}, horizontalArrangement = Arrangement.SpaceBetween) {
            listOf(bars.first(), bars[bars.size / 2], bars.last()).distinct().forEach {
                Text(axisLabel(it, byMonth, locale), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** Donut of category shares; the rows below are its legend. Each slice is a TalkBack node "name, x.x%". */
@Composable
private fun ExplorerDonut(trends: List<CategoryTrend>) {
    val colors = trends.map { categoryColor(it.colorToken) }
    val locale = Locale.getDefault()
    Box(modifier = Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
        Canvas(modifier = Modifier.size(200.dp)) {
            val stroke = size.minDimension * 0.45f / 2
            val inset = stroke / 2
            val arcSize = Size(size.minDimension - stroke, size.minDimension - stroke)
            val gap = if (trends.size > 1) 2f else 0f
            var angle = -90f
            trends.forEachIndexed { index, trend ->
                val sweep = (trend.share / 100 * 360).toFloat()
                if (sweep - gap > 0f) {
                    drawArc(colors[index], angle + gap / 2, sweep - gap, useCenter = false, topLeft = Offset(inset, inset), size = arcSize, style = Stroke(stroke))
                }
                angle += sweep
            }
        }
        Column(modifier = Modifier.size(200.dp)) {
            trends.forEach { trend ->
                val description = "${categoryDisplayName(trend.label)}, ${String.format(locale, "%.1f%%", trend.share)}"
                Box(Modifier.weight(1f).fillMaxWidth().semantics { contentDescription = description })
            }
        }
    }
}

/** A category's amount, share and Δ — iOS `CategoryTrendRow` at b649dff. */
@Composable
internal fun CategoryTrendRow(trend: CategoryTrend, isIncome: Boolean, currencyCode: String, onClick: () -> Unit) {
    val extended = LocalFinanceExtendedColors.current
    val locale = Locale.getDefault()
    val name = categoryDisplayName(trend.label)
    val share = stringResource(R.string.explorer_share, String.format(locale, "%.1f", trend.share))
    val amount = formatCurrency(trend.amount, currencyCode)
    val percent = abs(trend.changePercent).roundToInt()
    val change = when {
        trend.isNew -> stringResource(R.string.explorer_new)
        trend.direction == TrendDirection.UP -> stringResource(R.string.explorer_up, percent)
        trend.direction == TrendDirection.DOWN -> stringResource(R.string.explorer_down, percent)
        else -> stringResource(R.string.explorer_same)
    }
    // Income rising is good news, spending rising isn't.
    val trendColor = when (trend.direction) {
        TrendDirection.UP -> if (isIncome) extended.positive else extended.negative
        TrendDirection.DOWN -> if (isIncome) extended.negative else extended.positive
        TrendDirection.FLAT -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    val tint = categoryColor(trend.colorToken)
    val hint = stringResource(R.string.explorer_row_hint)
    FinanceCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClickLabel = hint, role = Role.Button, onClick = onClick)
            .clearAndSetSemantics {
                contentDescription = name
                stateDescription = listOf(amount, share, change).joinToString(", ")
                role = Role.Button
                onClick(label = hint) { onClick(); true }
            },
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                modifier = Modifier.size(42.dp).background(tint.copy(alpha = 0.18f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(categoryIconFor(trend.category?.iconToken.orEmpty()), contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(name, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(share, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(amount, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                TrendBadge(trend, trendColor)
            }
        }
    }
}

@Composable
private fun TrendBadge(trend: CategoryTrend, color: Color) {
    val badgeColor = if (trend.isNew) MaterialTheme.colorScheme.onSurfaceVariant else color
    Row(
        modifier = Modifier
            .background(badgeColor.copy(alpha = 0.12f), RoundedCornerShape(50))
            .padding(horizontal = 6.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        if (trend.isNew) {
            Text(stringResource(R.string.explorer_new), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = badgeColor)
        } else {
            Icon(
                when (trend.direction) {
                    TrendDirection.UP -> Icons.Outlined.ArrowUpward
                    TrendDirection.DOWN -> Icons.Outlined.ArrowDownward
                    TrendDirection.FLAT -> Icons.Outlined.Remove
                },
                contentDescription = null,
                tint = badgeColor,
                modifier = Modifier.size(12.dp),
            )
            Text(
                String.format(Locale.getDefault(), "%.0f%%", abs(trend.changePercent)),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = badgeColor,
            )
        }
    }
}

/**
 * What a category row drills into: that category's rows for the period and type the explorer was
 * showing. A value, not a captured list, so the screen re-derives its rows and edits show (iOS
 * `ExplorerDrillDown`). Saveable, so it survives recreation.
 */
internal data class ExplorerDrillDown(
    val label: String,
    val type: ExplorerType,
    val granularity: ExplorerGranularity,
    val startMillis: Long,
    val endMillis: Long,
) {
    val period get() = ExplorerPeriod(granularity, Instant.ofEpochMilli(startMillis), Instant.ofEpochMilli(endMillis))

    companion object {
        fun of(trend: CategoryTrend, period: ExplorerPeriod, type: ExplorerType) =
            ExplorerDrillDown(trend.label, type, period.granularity, period.start.toEpochMilli(), period.end.toEpochMilli())

        val Saver = androidx.compose.runtime.saveable.listSaver<ExplorerDrillDown?, Any>(
            save = { it?.let { d -> listOf(d.label, d.type.name, d.granularity.name, d.startMillis, d.endMillis) }.orEmpty() },
            restore = {
                if (it.isEmpty()) null else ExplorerDrillDown(
                    it[0] as String,
                    ExplorerType.valueOf(it[1] as String),
                    ExplorerGranularity.valueOf(it[2] as String),
                    it[3] as Long,
                    it[4] as Long,
                )
            },
        )
    }
}
