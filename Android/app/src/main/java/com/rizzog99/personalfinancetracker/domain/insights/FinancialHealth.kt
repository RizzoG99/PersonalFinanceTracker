package com.rizzog99.personalfinancetracker.domain.insights

import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.insight.HealthScoreSnapshot
import com.rizzog99.personalfinancetracker.domain.paycycle.PayCycleService
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.math.MathContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlin.math.sqrt

enum class HealthBand {
    EXCELLENT, SOLID, PROGRESS, ATTENTION;

    companion object {
        fun of(score: Int) = when {
            score >= 80 -> EXCELLENT
            score >= 60 -> SOLID
            score >= 40 -> PROGRESS
            else -> ATTENTION
        }
    }
}

enum class HealthComponentKind { SAVINGS, STABILITY, BUDGET, SUBSCRIPTIONS }

/**
 * One component and the facts its explanation and tip are written from (the copy lives in the UI).
 * [percent] is the savings rate, spending variation or subscription share, `Int(x × 100)` as iOS.
 */
data class HealthComponent(
    val kind: HealthComponentKind,
    val score: Int,
    val max: Int,
    val percent: Int = 0,
    val adhering: Int = 0,
    val budgeted: Int = 0,
    /** Whole euros more per month to reach a 20 % savings rate (savings only). */
    val monthlyGap: Int = 0,
) {
    val hasTip: Boolean get() = score < max
}

data class HealthScore(val score: Int, val band: HealthBand, val components: List<HealthComponent>) {
    fun scoreOf(kind: HealthComponentKind) = components.firstOrNull { it.kind == kind }?.score ?: 0
}

/**
 * iOS `FinancialHealthService.compute` at b649dff (#304), over the six pay cycles ending with the
 * one containing [today]. Cycles are whole dates, so a cycle's last day counts (iOS #342, D-01).
 * Null when the window holds neither income nor spending, as iOS shows no score then.
 */
fun computeHealthScore(
    transactions: List<FinanceTransaction>,
    categories: List<FinanceCategory>,
    payCycleStartDay: Int,
    ignoreSubscriptions: Boolean,
    today: LocalDate,
    zone: ZoneId,
): HealthScore? {
    val cycles = PayCycleService.financialMonths(6, today, payCycleStartDay)
    val windowStart = cycles.first().start
    fun FinanceTransaction.date() = timestamp.atZone(zone).toLocalDate()
    // Spending leaves goal transfers out: saved, not spent (iOS `InsightsViewModel.swift:158`).
    val expenses = transactions.filter { it.amount.signum() < 0 && it.goalId == null }
    val recent = transactions.filter { !it.date().isBefore(windowStart) }
    val recentExpenses = expenses.filter { !it.date().isBefore(windowStart) }
    if (recent.none { it.amount.signum() > 0 } && recentExpenses.isEmpty()) return null

    // 1. Savings rate: 20 % earns full marks.
    val income = recent.filter { it.amount.signum() > 0 }.sum()
    val spent = recentExpenses.sum()
    // Decimal division, then one conversion, as iOS: €80.16 of €100.20 is exactly 20 % (25 points).
    val rate = if (income.signum() > 0) income.subtract(spent).divide(income, MathContext.DECIMAL64).toDouble() else 0.0
    val savings = (rate / 0.20 * 25).toInt().coerceIn(0, 25)
    // iOS rounds the rate to 6 decimals before the gap, then truncates whole euros.
    val rate6 = BigDecimal(String.format(Locale.US, "%.6f", rate))
    val gap = BigDecimal("0.20").subtract(rate6).max(BigDecimal.ZERO).multiply(income).divide(BigDecimal(6), 6, java.math.RoundingMode.DOWN)

    // 2. Stability: coefficient of variation of the six cycle totals.
    val monthly = cycles.map { cycle -> expenses.filter { it.date() in cycle }.sum().toDouble() }
    val mean = monthly.sum() / 6
    val variance = if (mean > 0) monthly.sumOf { (it - mean) * (it - mean) } / 6 else 0.0
    val cov = if (mean > 0) sqrt(variance) / mean else 0.0
    val stability = ((1.0 - cov / 0.5) * 25).toInt().coerceIn(0, 25)

    // 3. Budget adherence, current cycle; a label matches a budget when it contains its name.
    val current = cycles.last()
    val budgeted = categories.filter { it.monthlyBudget != null }
    val thisCycle = expenses.filter { it.date() in current }
    val adhering = budgeted.count { category ->
        thisCycle.filter { it.categoryLabel.contains(category.name, ignoreCase = true) }.sum() <= requireNotNull(category.monthlyBudget)
    }
    val adherence = if (budgeted.isEmpty()) 25 else (adhering.toDouble() / budgeted.size * 25).toInt()

    // 4. Subscriptions: over 15 % of spending scores 0.
    val subscriptionSpend = recentExpenses.filter {
        it.categoryLabel.contains("subscri", ignoreCase = true) || it.categoryLabel.contains("stream", ignoreCase = true)
    }.sum()
    val ratio = if (spent.signum() > 0) subscriptionSpend.divide(spent, MathContext.DECIMAL64).toDouble() else 0.0
    val subscriptions = subscriptionScore(ratio)

    fun savingsOf(score: Int, max: Int) =
        HealthComponent(HealthComponentKind.SAVINGS, score, max, percent = (rate * 100).toInt(), monthlyGap = gap.toInt())
    fun stabilityOf(score: Int, max: Int) = HealthComponent(HealthComponentKind.STABILITY, score, max, percent = (cov * 100).toInt())
    fun budgetOf(score: Int, max: Int) = HealthComponent(HealthComponentKind.BUDGET, score, max, adhering = adhering, budgeted = budgeted.size)

    val components = if (ignoreSubscriptions) {
        // 100 points over three components: 34 / 33 / 33.
        listOf(
            savingsOf(minOf(34, (savings / 25.0 * 34).toInt()), 34),
            stabilityOf(minOf(33, (stability / 25.0 * 33).toInt()), 33),
            budgetOf(minOf(33, (adherence / 25.0 * 33).toInt()), 33),
        )
    } else {
        listOf(
            savingsOf(savings, 25),
            stabilityOf(stability, 25),
            budgetOf(adherence, 25),
            HealthComponent(HealthComponentKind.SUBSCRIPTIONS, subscriptions, 25, percent = (ratio * 100).toInt()),
        )
    }
    val total = components.sumOf { it.score }
    return HealthScore(total, HealthBand.of(total), components)
}

/** iOS `round()` rounds half away from zero; values here are ≥ 0 once clamped, so half up. */
internal fun subscriptionScore(ratio: Double): Int =
    Math.round(((1.0 - ratio / 0.15) * 25).coerceAtLeast(0.0)).toInt().coerceIn(0, 25)

/** The day's reading, as iOS `saveSnapshotIfNeeded` writes it (subscriptions 0 while ignored). */
fun HealthScore.snapshot(now: Instant): HealthScoreSnapshot = HealthScoreSnapshot(
    id = UUID.randomUUID().toString(),
    timestamp = now,
    score = score,
    savingsScore = scoreOf(HealthComponentKind.SAVINGS),
    stabilityScore = scoreOf(HealthComponentKind.STABILITY),
    adherenceScore = scoreOf(HealthComponentKind.BUDGET),
    subscriptionScore = scoreOf(HealthComponentKind.SUBSCRIPTIONS),
)

private fun List<FinanceTransaction>.sum(): BigDecimal = fold(BigDecimal.ZERO) { total, row -> total + row.amount.abs() }
