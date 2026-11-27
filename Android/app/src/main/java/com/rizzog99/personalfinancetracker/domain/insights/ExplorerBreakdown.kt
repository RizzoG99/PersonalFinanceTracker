package com.rizzog99.personalfinancetracker.domain.insights

import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.math.MathContext
import java.time.Instant
import java.time.LocalDate

enum class ExplorerType { EXPENSES, INCOME }

enum class TrendDirection { UP, DOWN, FLAT }

/** One category row and pie slice: amount, share of the total, and Δ against the comparison window. */
data class CategoryTrend(
    val label: String,
    val amount: BigDecimal,
    /** Percent of the period's total, unrounded (shown as `%.1f`). */
    val share: Double,
    val changePercent: Double,
    val direction: TrendDirection,
    val isNew: Boolean,
    /** Supplies the row's own icon and colour (#291); null when no category owns the label. */
    val category: FinanceCategory?,
) {
    /** The category's own token, else iOS's name table (`PieChartDataService.swift:121-123`). */
    val colorToken: String get() = category?.colorToken ?: colorTokenForName(label)
}

/** One bar: a day, or the first day of a month when [ExplorerBreakdown.barsByMonth]. */
data class ExplorerBar(val day: LocalDate, val amount: BigDecimal)

/** Everything the explorer shows for one period and type. Port of iOS `ExplorerBreakdown.swift` at b649dff. */
data class ExplorerBreakdown(
    val trends: List<CategoryTrend>,
    val bars: List<ExplorerBar>,
    val barsByMonth: Boolean,
    val total: BigDecimal,
) {
    companion object {
        val EMPTY = ExplorerBreakdown(emptyList(), emptyList(), false, BigDecimal.ZERO)

        fun build(
            transactions: List<FinanceTransaction>,
            categories: List<FinanceCategory>,
            period: ExplorerPeriod,
            type: ExplorerType,
            now: Instant,
            calendar: ExplorerCalendar,
        ): ExplorerBreakdown {
            val items = explorerItems(transactions, period.start, period.end, type)
            val totals = totalsByLabel(items)
            val total = totals.values.fold(BigDecimal.ZERO, BigDecimal::add)

            // Δ compares pace: the running period is cut at now (a row dated later this month hasn't
            // happened yet, #154) and set against the same elapsed stretch of the previous period.
            val paceEnd = maxOf(period.start, minOf(period.end, now))
            val pace = totalsByLabel(explorerItems(transactions, period.start, paceEnd, type))
            val comparison = period.comparisonInterval(now, calendar)
            val previous = totalsByLabel(explorerItems(transactions, comparison.start, comparison.end, type))

            val categoryType = if (type == ExplorerType.INCOME) TransactionType.INCOME else TransactionType.EXPENSE
            // An income and an expense category can share a name ("Other"): take the one of this type.
            val byName = categories.filter { it.type == categoryType }.groupBy { it.name }.mapValues { it.value.first() }
            val byId = categories.associateBy { it.id }

            val trends = totals.entries.sortedByDescending { it.value }.map { (label, amount) ->
                val current = pace[label]
                val prev = previous[label] ?: BigDecimal.ZERO
                // Decimal, like iOS: €0.63 vs €0.60 is exactly +5 % (flat), not 5.000…04 % (up).
                val change = if (current != null && prev.signum() > 0) {
                    current.subtract(prev).multiply(HUNDRED).divide(prev, MathContext.DECIMAL64).toDouble()
                } else {
                    0.0
                }
                CategoryTrend(
                    label = label,
                    amount = amount,
                    // Decimal first, like iOS: €0.11 of €0.80 is exactly 13.75 → "13.8%", not 13.7.
                    share = if (total.signum() > 0) amount.multiply(HUNDRED).divide(total, MathContext.DECIMAL64).toDouble() else 0.0,
                    changePercent = change,
                    // A category whose only rows are still ahead of now has no pace yet: flat, not "new".
                    direction = when {
                        current == null -> TrendDirection.FLAT
                        change > 5 -> TrendDirection.UP
                        change < -5 -> TrendDirection.DOWN
                        else -> TrendDirection.FLAT
                    },
                    isNew = current != null && prev.signum() == 0 && current.signum() > 0,
                    category = byName[label] ?: items.firstNotNullOfOrNull { item ->
                        item.categoryId?.takeIf { groupingKey(item) == label }?.let(byId::get)
                    },
                )
            }

            // ponytail: 62 days ≈ two months of daily bars; past that a bar per day is unreadable (iOS).
            val byMonth = period.granularity == ExplorerGranularity.YEAR || period.days(calendar) > 62
            val bucket: (LocalDate) -> LocalDate = if (byMonth) { day -> day.withDayOfMonth(1) } else { day -> day }
            val sums = items.groupBy { bucket(calendar.date(it.timestamp)) }
                .mapValues { (_, rows) -> rows.fold(BigDecimal.ZERO) { sum, row -> sum + row.amount.abs() } }
            // Every bucket of the period, empty ones included, so the axis covers the whole period.
            val last = calendar.date(period.end)
            val bars = generateSequence(bucket(calendar.date(period.start))) { if (byMonth) it.plusMonths(1) else it.plusDays(1) }
                .takeWhile { it < last }
                .map { ExplorerBar(it, sums[it] ?: BigDecimal.ZERO) }
                .toList()

            return ExplorerBreakdown(trends, bars, byMonth, total)
        }
    }
}

/**
 * The explorer's one filter: inside [start, end), of [type], every goal-linked row left out (D-01,
 * iOS `PieChartDataService.explorerItems`). Slices, bars and a row's drill-down all go through it,
 * so a row's amount always equals the sum of what it drills into.
 */
fun explorerItems(transactions: List<FinanceTransaction>, start: Instant, end: Instant, type: ExplorerType): List<FinanceTransaction> =
    transactions.filter {
        it.goalId == null && it.timestamp >= start && it.timestamp < end &&
            if (type == ExplorerType.INCOME) it.amount.signum() > 0 else it.amount.signum() < 0
    }

/** A row's drill-down: its transactions for the period and type, newest first. */
fun drillDown(transactions: List<FinanceTransaction>, label: String, period: ExplorerPeriod, type: ExplorerType): List<FinanceTransaction> =
    explorerItems(transactions, period.start, period.end, type)
        .filter { groupingKey(it) == label }
        .sortedByDescending { it.timestamp }

/** The label a row groups under (iOS: an empty label is "Other"). */
fun groupingKey(transaction: FinanceTransaction): String = transaction.categoryLabel.ifEmpty { "Other" }

private val HUNDRED = BigDecimal(100)

/** iOS `CategoryConstants.colorToken(forName:)` at b649dff: the colour of a label no category owns. */
fun colorTokenForName(name: String): String {
    val lower = name.lowercase()
    fun has(vararg words: String) = words.any { lower.contains(it) }
    return when {
        has("grocer", "salary", "gift", "invest", "freelance", "bonus", "prize", "refund", "rental") -> "categoryGreen"
        has("restaurant", "coffee", "takeout", "dining", "food", "entertainment") -> "categoryAmber"
        has("gas", "car ", "transport", "taxi", "rideshare", "rent", "mortgage", "utilities", "phone", "internet", "banking") ||
            lower == "car" -> "categoryIndigo"
        has("shopping", "clothing", "electronics") -> "categoryPink"
        has("streaming", "subscription", "music", "hobbies", "books") -> "categoryPurple"
        has("health", "gym", "fitness", "pharmacy", "pet", "personal care", "education") -> "categoryTeal"
        has("travel") -> "categoryAmber"
        else -> "categoryGray"
    }
}

private fun totalsByLabel(items: List<FinanceTransaction>): Map<String, BigDecimal> =
    items.groupBy(::groupingKey).mapValues { (_, rows) -> rows.fold(BigDecimal.ZERO) { sum, row -> sum + row.amount.abs() } }
