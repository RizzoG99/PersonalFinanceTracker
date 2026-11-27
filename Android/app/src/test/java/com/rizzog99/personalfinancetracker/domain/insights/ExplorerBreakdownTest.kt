package com.rizzog99.personalfinancetracker.domain.insights

import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #303 Breakdown explorer, fixture F of the issue. Ports iOS `ExplorerTests.swift` and
 * `ExplorerBreakdown.swift` / `ExplorerPeriod.swift` at b649dff.
 */
class ExplorerBreakdownTest {
    private val zone: ZoneId = ZoneId.of("Europe/Rome")
    private val calendar = ExplorerCalendar(zone, DayOfWeek.MONDAY)
    private val now: Instant = at(2026, 9, 10, 12)

    private fun at(y: Int, m: Int, d: Int, h: Int = 12, min: Int = 0): Instant =
        LocalDateTime.of(y, m, d, h, min).atZone(zone).toInstant()

    private fun tx(id: String, amount: String, label: String, day: Instant, goalId: String? = null, categoryId: String? = null) =
        FinanceTransaction(id, day, BigDecimal(amount), "", label, categoryId, "EUR", goalId, null)

    private val fixture = listOf(
        tx("f1", "-100", "Food", at(2026, 8, 5)),
        tx("f2", "-200", "Food", at(2026, 8, 20)),
        tx("s", "2000", "Salary", at(2026, 9, 1)),
        tx("f3", "-60", "Food", at(2026, 9, 3)),
        tx("fun", "-50", "Fun", at(2026, 9, 5)),
        tx("t", "-500", "→ Holiday", at(2026, 9, 6), goalId = "goal"),
        tx("f4", "-90", "Food", at(2026, 9, 8)),
        tx("r", "-800", "Rent", at(2026, 9, 25)),
    )

    private val september = ExplorerPeriod.current(ExplorerGranularity.MONTH, now, calendar)

    private fun build(
        period: ExplorerPeriod = september,
        type: ExplorerType = ExplorerType.EXPENSES,
        transactions: List<FinanceTransaction> = fixture,
        categories: List<FinanceCategory> = emptyList(),
    ) = ExplorerBreakdown.build(transactions, categories, period, type, now, calendar)

    private fun assertMoney(expected: String, actual: BigDecimal) = assertEquals(0, BigDecimal(expected).compareTo(actual))

    @Test
    fun ac01_septemberExpenses() {
        val breakdown = build()
        assertMoney("1000", breakdown.total)
        assertEquals(listOf("Rent", "Food", "Fun"), breakdown.trends.map { it.label })
        val (rent, food, fun_) = breakdown.trends
        assertMoney("800", rent.amount)
        assertEquals(80.0, rent.share, 0.001)
        // Only ahead of now: no pace yet, so flat, not new.
        assertEquals(TrendDirection.FLAT, rent.direction)
        assertFalse(rent.isNew)
        assertMoney("150", food.amount)
        assertEquals(15.0, food.share, 0.001)
        assertEquals(TrendDirection.UP, food.direction)
        assertEquals(50.0, food.changePercent, 0.001)
        assertEquals(5.0, fun_.share, 0.001)
        assertTrue(fun_.isNew)
        assertEquals(0.0, fun_.changePercent, 0.0)

        assertFalse(breakdown.barsByMonth)
        assertEquals(30, breakdown.bars.size)
        assertEquals(LocalDate.of(2026, 9, 1), breakdown.bars.first().day)
        assertMoney("1000", breakdown.bars.fold(BigDecimal.ZERO) { sum, bar -> sum + bar.amount })
        assertMoney("800", breakdown.bars.single { it.day == LocalDate.of(2026, 9, 25) }.amount)
        assertMoney("0", breakdown.bars.single { it.day == LocalDate.of(2026, 9, 6) }.amount)
    }

    /** D-01: the explorer drops every goal-linked row, as iOS `explorerItems` does, income too. */
    @Test
    fun ac01_goalLinkedRowsExcludedInBothModes() {
        val withRefund = fixture + tx("back", "30", "← Holiday", at(2026, 9, 7), goalId = "goal")
        val income = build(type = ExplorerType.INCOME, transactions = withRefund)
        assertEquals(listOf("Salary"), income.trends.map { it.label })
        assertTrue(build(transactions = withRefund).trends.none { it.label.contains("Holiday") })
    }

    @Test
    fun ac02_incomeAndEmptyPeriod() {
        val income = build(type = ExplorerType.INCOME)
        val salary = income.trends.single()
        assertEquals("Salary", salary.label)
        assertMoney("2000", salary.amount)
        assertEquals(100.0, salary.share, 0.001)
        assertTrue(salary.isNew)

        val augustIncome = build(period = september.previous(calendar), type = ExplorerType.INCOME)
        assertTrue(augustIncome.trends.isEmpty())
        assertMoney("0", augustIncome.total)
    }

    @Test
    fun ac03_navigationBounds() {
        assertTrue(september.isCurrent(now))
        val august = september.previous(calendar)
        assertEquals(at(2026, 8, 1, 0), august.start)
        assertEquals(at(2026, 9, 1, 0), august.end)
        assertFalse(august.isCurrent(now))
        val first = fixture.minOf { it.timestamp }
        assertTrue("‹ allowed from September", canGoPrevious(september, first, calendar))
        assertFalse("‹ stops at August", canGoPrevious(august, first, calendar))
        assertFalse(canGoPrevious(september, null, calendar))

        val aug = build(period = august)
        assertEquals(listOf("Food"), aug.trends.map { it.label })
        assertTrue(aug.trends.single().isNew)
        assertEquals(100.0, aug.trends.single().share, 0.001)

        // Stays around the viewed date (iOS `BreakdownExplorerSection.swift:94`).
        val year = august.withGranularity(ExplorerGranularity.YEAR, calendar)
        assertEquals(at(2026, 1, 1, 0), year.start)
        val yearBreakdown = build(period = year)
        assertTrue(yearBreakdown.barsByMonth)
        assertEquals(12, yearBreakdown.bars.size)
        assertMoney("300", yearBreakdown.bars.single { it.day == LocalDate.of(2026, 8, 1) }.amount)

        val week = ExplorerPeriod.current(ExplorerGranularity.WEEK, now, calendar)
        assertEquals(at(2026, 9, 7, 0), week.start)
        assertEquals(at(2026, 9, 14, 0), week.end)
        val sundayWeek = ExplorerPeriod.current(ExplorerGranularity.WEEK, now, ExplorerCalendar(zone, DayOfWeek.SUNDAY))
        assertEquals(at(2026, 9, 6, 0), sundayWeek.start)
        val previousYearEnd = ExplorerPeriod.current(ExplorerGranularity.WEEK, at(2026, 1, 1), calendar).previous(calendar)
        assertEquals(at(2025, 12, 22, 0), previousYearEnd.start)
    }

    @Test
    fun ac04_customRangeIsWholeDaysAndStepsByItsLength() {
        val custom = ExplorerPeriod.custom(LocalDate.of(2026, 8, 12), LocalDate.of(2026, 8, 3), calendar)
        assertEquals(ExplorerGranularity.CUSTOM, custom.granularity)
        assertEquals(at(2026, 8, 3, 0), custom.start)
        assertEquals(at(2026, 8, 13, 0), custom.end)
        val previous = custom.previous(calendar)
        assertEquals(at(2026, 7, 24, 0), previous.start)
        assertEquals(at(2026, 8, 3, 0), previous.end)
        assertEquals(TimeRange(previous.start, previous.end), custom.comparisonInterval(now, calendar))
        assertEquals(10, build(period = custom).bars.size)
        val long = ExplorerPeriod.custom(LocalDate.of(2026, 1, 1), LocalDate.of(2026, 3, 31), calendar)
        assertTrue("> 62 days → month bars", build(period = long).barsByMonth)
        assertEquals(3, build(period = long).bars.size)
    }

    @Test
    fun ac05_comparisonWindows() {
        val august = september.previous(calendar)
        assertEquals(TimeRange(at(2026, 7, 1, 0), at(2026, 8, 1, 0)), august.comparisonInterval(now, calendar))
        assertEquals(TimeRange(at(2026, 8, 1, 0), at(2026, 8, 10, 12)), september.comparisonInterval(now, calendar))
        for (year in listOf(2026, 2028)) {
            val march31 = at(year, 3, 31, 12)
            val march = ExplorerPeriod.current(ExplorerGranularity.MONTH, march31, calendar)
            assertEquals(TimeRange(at(year, 2, 1, 0), at(year, 3, 1, 0)), march.comparisonInterval(march31, calendar))
        }
    }

    @Test
    fun ac06_everyRowEqualsItsDrillDown() {
        val breakdown = build()
        breakdown.trends.forEach { trend ->
            val rows = drillDown(fixture, trend.label, september, ExplorerType.EXPENSES)
            assertMoney(trend.amount.toPlainString(), rows.fold(BigDecimal.ZERO) { sum, row -> sum + row.amount.abs() })
        }
        assertEquals(listOf("f4", "f3"), drillDown(fixture, "Food", september, ExplorerType.EXPENSES).map { it.id })
        // iOS groups only an empty label under "Other" (`PieChartDataService.swift:205`).
        val labels = build(transactions = listOf(tx("x", "-5", "", at(2026, 9, 2)), tx("y", "-4", " ", at(2026, 9, 2)))).trends.map { it.label }
        assertEquals(listOf("Other", " "), labels)
    }

    /** iOS thresholds are strict (> 5, < −5) on a Decimal Δ: exactly ±5 % stays flat. */
    @Test
    fun ac01_deltaThresholdsAreExact() {
        fun direction(previous: String, current: String) = build(
            transactions = listOf(tx("p", previous, "A", at(2026, 8, 2)), tx("c", current, "A", at(2026, 9, 2))),
        ).trends.single().direction
        assertEquals(TrendDirection.FLAT, direction("-0.60", "-0.63"))
        assertEquals(TrendDirection.FLAT, direction("-0.60", "-0.57"))
        assertEquals(TrendDirection.UP, direction("-0.60", "-0.64"))
        assertEquals(TrendDirection.DOWN, direction("-0.60", "-0.56"))
    }

    @Test
    fun ac01_shareIsNotRoundedEarly() {
        val thirds = build(transactions = listOf(tx("a", "-1", "A", at(2026, 9, 2)), tx("b", "-2", "B", at(2026, 9, 2))))
        assertEquals(100.0 / 3, thirds.trends.single { it.label == "A" }.share, 1e-9)
        // €0.11 of €0.80 is exactly 13.75: double-first division gives 13.7499… and shows 13.7.
        val boundary = build(transactions = listOf(tx("a", "-0.11", "A", at(2026, 9, 2)), tx("b", "-0.69", "B", at(2026, 9, 2))))
        assertEquals("13.8", String.format(java.util.Locale.US, "%.1f", boundary.trends.single { it.label == "A" }.share))
    }

    @Test
    fun ac04_pickerBounds() {
        val first = at(2026, 8, 5, 9)
        val bounds = customRangeBounds(first, now, september, calendar)
        assertEquals(LocalDate.of(2026, 8, 5), bounds.earliest)
        assertEquals(LocalDate.of(2026, 9, 10), bounds.latest)
        assertEquals(LocalDate.of(2026, 9, 1), bounds.initialFrom)
        assertEquals(LocalDate.of(2026, 9, 10), bounds.initialTo)
        // No history, or history only in the future: the earliest day is today, never after it.
        listOf(null, at(2026, 9, 25)).forEach { firstOrFuture ->
            val clamped = customRangeBounds(firstOrFuture, now, september, calendar)
            assertEquals(LocalDate.of(2026, 9, 10), clamped.earliest)
            assertEquals(LocalDate.of(2026, 9, 10), clamped.initialFrom)
        }
        val august = customRangeBounds(first, now, september.previous(calendar), calendar)
        assertEquals(LocalDate.of(2026, 8, 5) to LocalDate.of(2026, 8, 31), august.initialFrom to august.initialTo)
    }

    @Test
    fun ac08_rowsCarryTheirOwnCategory() {
        val climbing = FinanceCategory("c1", "Climbing", "figure.climbing", TransactionType.EXPENSE, "categoryPink", null, "EUR")
        val otherIncome = FinanceCategory("o-in", "Other", "banknote", TransactionType.INCOME, "categoryGreen", null, "EUR")
        val otherExpense = FinanceCategory("o-ex", "Other", "questionmark", TransactionType.EXPENSE, "categoryRed", null, "EUR")
        val linkedOnly = FinanceCategory("l1", "Renamed", "cart", TransactionType.EXPENSE, "categoryTeal", null, "EUR")
        val txs = listOf(
            tx("a", "-40", "Climbing", at(2026, 9, 2)),
            tx("b", "-10", "Other", at(2026, 9, 2)),
            tx("c", "-5", "Old name", at(2026, 9, 2), categoryId = "l1"),
            tx("d", "-1", "Loose", at(2026, 9, 2)),
        )
        val rows = build(transactions = txs, categories = listOf(otherIncome, climbing, otherExpense, linkedOnly)).trends.associateBy { it.label }
        assertEquals(climbing, rows.getValue("Climbing").category)
        assertEquals(otherExpense, rows.getValue("Other").category)
        assertEquals(linkedOnly, rows.getValue("Old name").category)
        assertNull(rows.getValue("Loose").category)
        assertEquals("categoryPink", rows.getValue("Climbing").colorToken)
        assertEquals("categoryGray", rows.getValue("Loose").colorToken)
        // No category owns "Food" here: iOS's name table still colours it (`CategoryConstants.swift:126-128`).
        assertEquals("categoryAmber", build(transactions = listOf(tx("f", "-3", "Food", at(2026, 9, 2)))).trends.single().colorToken)
    }
}
