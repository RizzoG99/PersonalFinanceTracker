package com.rizzog99.personalfinancetracker.features.insights

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.insight.HealthScoreSnapshot
import com.rizzog99.personalfinancetracker.domain.insights.HealthBand
import com.rizzog99.personalfinancetracker.domain.insights.HealthComponent
import com.rizzog99.personalfinancetracker.domain.insights.HealthComponentKind
import com.rizzog99.personalfinancetracker.domain.insights.HealthScore
import com.rizzog99.personalfinancetracker.domain.paycycle.PayCycleService
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.components.coverWhenObscured
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinanceExtendedColors
import java.math.BigDecimal
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/** iOS band colours: positive, indigo, amber, negative (`HealthScoreCard.swift:8-15`). */
@Composable
internal fun healthBandColor(band: HealthBand): Color {
    val extended = LocalFinanceExtendedColors.current
    return when (band) {
        HealthBand.EXCELLENT -> extended.positive
        HealthBand.SOLID -> extended.categoryIndigo
        HealthBand.PROGRESS -> extended.categoryAmber
        HealthBand.ATTENTION -> extended.negative
    }
}

@Composable
internal fun healthBandLabel(band: HealthBand): String = stringResource(
    when (band) {
        HealthBand.EXCELLENT -> R.string.health_band_excellent
        HealthBand.SOLID -> R.string.health_band_solid
        HealthBand.PROGRESS -> R.string.health_band_progress
        HealthBand.ATTENTION -> R.string.health_band_attention
    },
)

@Composable
private fun componentName(kind: HealthComponentKind): String = stringResource(
    when (kind) {
        HealthComponentKind.SAVINGS -> R.string.health_component_savings
        HealthComponentKind.STABILITY -> R.string.health_component_stability
        HealthComponentKind.BUDGET -> R.string.health_component_budget
        HealthComponentKind.SUBSCRIPTIONS -> R.string.health_component_subscriptions
    },
)

/** iOS `FinancialHealthService` explanation helpers. */
@Composable
private fun explanation(component: HealthComponent): String = when (component.kind) {
    HealthComponentKind.SAVINGS -> stringResource(R.string.health_explain_savings, component.percent)
    HealthComponentKind.STABILITY -> stringResource(R.string.health_explain_stability, component.percent)
    HealthComponentKind.BUDGET -> if (component.budgeted == 0) {
        stringResource(R.string.health_explain_budget_none)
    } else {
        stringResource(R.string.health_explain_budget, component.adhering, component.budgeted)
    }
    HealthComponentKind.SUBSCRIPTIONS -> if (component.percent > 0) {
        stringResource(R.string.health_explain_subscriptions, component.percent)
    } else {
        stringResource(R.string.health_explain_subscriptions_none)
    }
}

/** iOS tip helpers; null when the component is at its maximum. */
@Composable
private fun tip(component: HealthComponent, currencyCode: String): String? {
    if (!component.hasTip) return null
    return when (component.kind) {
        HealthComponentKind.SAVINGS -> if (component.monthlyGap >= 1) {
            stringResource(R.string.health_tip_savings_amount, formatCurrency(BigDecimal(component.monthlyGap), currencyCode))
        } else {
            stringResource(R.string.health_tip_savings_rate, component.percent)
        }
        HealthComponentKind.STABILITY -> stringResource(R.string.health_tip_stability, component.percent)
        HealthComponentKind.BUDGET -> if (component.budgeted == 0) {
            stringResource(R.string.health_tip_budget_none)
        } else {
            val over = component.budgeted - component.adhering
            pluralStringResource(R.plurals.health_tip_budget, over, over)
        }
        HealthComponentKind.SUBSCRIPTIONS -> stringResource(R.string.health_tip_subscriptions, 15)
    }
}

/** Insights' Health Score section (iOS `HealthScoreSection`): heading, then the card or the empty state. */
@Composable
internal fun HealthScoreSection(health: HealthScore?, onOpen: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.health_score), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
        Text(stringResource(R.string.health_score_detail), color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (health == null) HealthScoreEmpty() else HealthScoreCard(health, onOpen)
    }
}

@Composable
internal fun HealthScoreEmpty(modifier: Modifier = Modifier) {
    FinanceCard(modifier = modifier) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Outlined.Speed, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(32.dp))
            Text(stringResource(R.string.health_score_empty), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Text(stringResource(R.string.health_score_empty_detail), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** iOS `HealthScoreCard`: arc gauge in the band colour, "N / 100", the label, a row per component. */
@Composable
private fun HealthScoreCard(health: HealthScore, onOpen: () -> Unit) {
    val color = healthBandColor(health.band)
    FinanceCard(
        modifier = Modifier.fillMaxWidth().testTag(HEALTH_CARD_TAG)
            .clickable(onClickLabel = stringResource(R.string.health_open_hint), role = Role.Button, onClick = onOpen),
    ) {
        val details: @Composable (Modifier) -> Unit = { modifier ->
            Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.health_score_value, health.score), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text(healthBandLabel(health.band), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                health.components.forEach { component -> ComponentRow(component, color) }
            }
        }
        // Large text: the gauge goes on top, or the component names break mid-word beside it
        // (same threshold as Activity's summary cards).
        if (androidx.compose.ui.platform.LocalDensity.current.fontScale >= 1.3f) {
            Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                ArcGauge(health.score, color, Modifier.size(100.dp))
                details(Modifier.fillMaxWidth())
            }
        } else {
            Row(
                modifier = Modifier.fillMaxWidth().padding(20.dp),
                horizontalArrangement = Arrangement.spacedBy(20.dp),
                verticalAlignment = Alignment.Top,
            ) {
                ArcGauge(health.score, color, Modifier.size(100.dp))
                details(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun ComponentRow(component: HealthComponent, color: Color) {
    val name = componentName(component.kind)
    val a11y = stringResource(R.string.health_component_a11y, name, component.score, component.max)
    Row(
        modifier = Modifier.clearAndSetSemantics { contentDescription = a11y },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(name, modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        ScoreBar(component.score.toFloat() / component.max, color.copy(alpha = 0.8f), Modifier.width(60.dp).height(5.dp))
        Text(
            stringResource(R.string.health_component_value, component.score, component.max).replace(" ", ""),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
        )
    }
}

@Composable
private fun ScoreBar(fraction: Float, color: Color, modifier: Modifier) {
    Box(modifier.clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.outlineVariant)) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).fillMaxHeight().clip(RoundedCornerShape(50)).background(color))
    }
}

/** iOS `ArcGaugeView`: an 80 % arc open at the bottom, the score inside. */
@Composable
private fun ArcGauge(score: Int, color: Color, modifier: Modifier) {
    val track = MaterialTheme.colorScheme.outlineVariant
    val description = stringResource(R.string.health_score_value, score)
    Box(modifier.clearAndSetSemantics { contentDescription = description }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 10.dp.toPx()
            val inset = stroke / 2
            val arc = Size(size.minDimension - stroke, size.minDimension - stroke)
            drawArc(track, 126f, 288f, false, Offset(inset, inset), arc, style = Stroke(stroke, cap = StrokeCap.Round))
            drawArc(color, 126f, 288f * (score / 100f).coerceIn(0f, 1f), false, Offset(inset, inset), arc, style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("$score", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = color)
            Text(stringResource(R.string.health_score_label), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * iOS `HealthScoreDetailView`: score and legend, history (two or more snapshots), the breakdown
 * with explanations and tips, and the exclude switch. Hosted in a sheet on phones and as the wide
 * layout's Health Score page.
 */
@Composable
internal fun HealthScoreDetail(state: InsightsUiState, onIgnoreSubscriptions: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val health = state.health ?: return HealthScoreEmpty(modifier.padding(16.dp))
    val color = healthBandColor(health.band)
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        FinanceCard {
            Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("${health.score}", style = MaterialTheme.typography.displayMedium, fontWeight = FontWeight.Bold, color = color)
                    Text(stringResource(R.string.health_score_out_of), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(healthBandLabel(health.band), color = MaterialTheme.colorScheme.onSurfaceVariant)
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Legend()
            }
        }
        if (state.snapshots.size >= 2) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.health_history), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                FinanceCard { HistoryChart(state.snapshots, Modifier.fillMaxWidth().height(140.dp).padding(16.dp)) }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.explorer_breakdown), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Text(stringResource(R.string.health_breakdown_period, healthPeriod(state)), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            FinanceCard {
                Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    health.components.forEachIndexed { index, component ->
                        DetailComponent(component, state.currencyCode)
                        if (index < health.components.lastIndex) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }
            }
        }
        FinanceCard {
            // One toggle node: TalkBack reads the label, the detail and the state together.
            Row(
                Modifier.fillMaxWidth()
                    .toggleable(value = state.ignoreSubscriptions, role = Role.Switch, onValueChange = onIgnoreSubscriptions)
                    .padding(20.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(stringResource(R.string.health_exclude_subscriptions))
                    Text(stringResource(R.string.health_exclude_subscriptions_detail), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                // The row is the control; the switch is its picture, or TalkBack would stop on it twice.
                Switch(checked = state.ignoreSubscriptions, onCheckedChange = null, modifier = Modifier.clearAndSetSemantics {})
            }
        }
    }
}

/** "Apr 1 – Sep 15, 2026": the six-cycle window's first day to today (iOS `periodText`). */
@Composable
private fun healthPeriod(state: InsightsUiState): String {
    val today = state.now.atZone(state.zoneId).toLocalDate()
    val start = PayCycleService.financialMonths(6, today, state.payCycleStartDay).first().start
    val locale = Locale.getDefault()
    return DateTimeFormatter.ofPattern("MMM d", locale).format(start) + " – " +
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).format(today)
}

@Composable
private fun Legend() {
    val extended = LocalFinanceExtendedColors.current
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(stringResource(R.string.health_guide), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        val bands = listOf(
            Triple("80–100", R.string.health_legend_excellent, extended.positive),
            Triple("60–79", R.string.health_legend_solid, extended.categoryIndigo),
            Triple("40–59", R.string.health_legend_progress, extended.categoryAmber),
            Triple("< 40", R.string.health_legend_attention, extended.negative),
        )
        // Four across breaks the words at large text ("Excelle-nt"): two rows of two then.
        val perRow = if (androidx.compose.ui.platform.LocalDensity.current.fontScale >= 1.3f) 2 else 4
        bands.chunked(perRow).forEach { row ->
            Row(Modifier.fillMaxWidth()) {
                row.forEach { (range, label, color) ->
                    Column(Modifier.weight(1f).padding(end = 4.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Box(Modifier.fillMaxWidth().height(3.dp).background(color.copy(alpha = 0.6f), RoundedCornerShape(2.dp)))
                        Text(range, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = color)
                        Text(stringResource(label), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailComponent(component: HealthComponent, currencyCode: String) {
    val name = componentName(component.kind)
    val a11y = stringResource(R.string.health_component_a11y, name, component.score, component.max)
    val amber = LocalFinanceExtendedColors.current.categoryAmber
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            modifier = Modifier.clearAndSetSemantics { contentDescription = a11y },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(name, modifier = Modifier.weight(1f), fontWeight = FontWeight.Medium)
            Text(stringResource(R.string.health_component_value, component.score, component.max), fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        ScoreBar(component.score.toFloat() / component.max, MaterialTheme.colorScheme.primary.copy(alpha = 0.8f), Modifier.fillMaxWidth().height(6.dp))
        Text(explanation(component), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        tip(component, currencyCode)?.let { text ->
            Row(
                modifier = Modifier.background(amber.copy(alpha = 0.1f), RoundedCornerShape(8.dp)).padding(8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Icons.Outlined.Lightbulb, contentDescription = null, tint = amber, modifier = Modifier.size(14.dp))
                Text(text, style = MaterialTheme.typography.bodySmall, color = amber)
            }
        }
    }
}

/**
 * Score over time, as iOS's date-axis chart: points placed by timestamp (a gap of days shows as a
 * gap), a 0–100 scale labelled 0/50/100, the first and last dates below. A TalkBack node per point.
 */
@Composable
private fun HistoryChart(snapshots: List<HealthScoreSnapshot>, modifier: Modifier) {
    val points = snapshots.sortedBy { it.timestamp }
    val color = MaterialTheme.colorScheme.primary
    val grid = MaterialTheme.colorScheme.outlineVariant
    val labelStyle = MaterialTheme.typography.labelSmall
    val dim = MaterialTheme.colorScheme.onSurfaceVariant
    val zone = java.time.ZoneId.systemDefault()
    val formatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(Locale.getDefault()).withZone(zone)
    val axis = DateTimeFormatter.ofPattern("d MMM", Locale.getDefault()).withZone(zone)
    val first = points.first().timestamp.toEpochMilli()
    val span = (points.last().timestamp.toEpochMilli() - first).coerceAtLeast(1)
    fun x(snapshot: HealthScoreSnapshot) = (snapshot.timestamp.toEpochMilli() - first).toFloat() / span
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.weight(1f).fillMaxWidth()) {
            Box(Modifier.weight(1f).fillMaxHeight()) {
                Canvas(Modifier.fillMaxSize()) {
                    listOf(0f, 0.5f, 1f).forEach { y -> drawLine(grid, Offset(0f, size.height * y), Offset(size.width, size.height * y), 1.dp.toPx()) }
                    val offsets = points.map { Offset(x(it) * size.width, size.height * (1 - it.score / 100f)) }
                    offsets.zipWithNext { a, b -> drawLine(color, a, b, strokeWidth = 2.dp.toPx(), cap = StrokeCap.Round) }
                    offsets.forEach { drawCircle(color, 4.dp.toPx(), it) }
                }
                // Semantics only: one node per point, in time order, sized by its share of the axis.
                Row(Modifier.fillMaxSize()) {
                    points.forEach { snapshot ->
                        val description = stringResource(R.string.health_history_point, formatter.format(snapshot.timestamp), snapshot.score)
                        Box(Modifier.weight(1f).fillMaxHeight().semantics { contentDescription = description })
                    }
                }
            }
            Column(Modifier.fillMaxHeight().padding(start = 6.dp).clearAndSetSemantics {}, verticalArrangement = Arrangement.SpaceBetween) {
                listOf("100", "50", "0").forEach { Text(it, style = labelStyle, color = dim) }
            }
        }
        Row(Modifier.fillMaxWidth().clearAndSetSemantics {}, horizontalArrangement = Arrangement.SpaceBetween) {
            Text(axis.format(points.first().timestamp), style = labelStyle, color = dim)
            Text(axis.format(points.last().timestamp), style = labelStyle, color = dim)
        }
    }
}

/** The Health Score card's test hook: its texts merge into the clickable node. */
internal const val HEALTH_CARD_TAG = "healthScoreCard"

/** Phones: the detail as a full-height sheet (D-05), like iOS's large-detent sheet. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HealthScoreSheet(state: InsightsUiState, onIgnoreSubscriptions: (Boolean) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.coverWhenObscured()) {
            Text(
                stringResource(R.string.health_score),
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(horizontal = 16.dp).semantics { heading() },
            )
            HealthScoreDetail(state, onIgnoreSubscriptions, Modifier.fillMaxWidth())
        }
    }
}
