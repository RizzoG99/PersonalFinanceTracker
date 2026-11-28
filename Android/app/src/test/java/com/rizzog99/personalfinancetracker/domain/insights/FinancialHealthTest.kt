package com.rizzog99.personalfinancetracker.domain.insights

import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** #304 fixture H: iOS `FinancialHealthService` at b649dff, with iOS #342's last-day fix (D-01). */
class FinancialHealthTest {
    private val zone = ZoneId.of("Europe/Rome")
    private val today = LocalDate.of(2026, 9, 15)

    private fun at(m: Int, d: Int, h: Int = 12): Instant = LocalDateTime.of(2026, m, d, h, 0).atZone(zone).toInstant()
    private fun tx(id: String, amount: String, label: String, day: Instant, goalId: String? = null) =
        FinanceTransaction(id, day, BigDecimal(amount), "", label, null, "EUR", goalId, null)
    private fun budget(name: String, amount: String) =
        FinanceCategory(name.lowercase(), name, "cart", TransactionType.EXPENSE, "categoryGreen", BigDecimal(amount), "EUR")

    private val fixture = (4..9).map { tx("salary-$it", "1200", "Salary", at(it, 1)) } + listOf(
        tx("apr", "-1000", "Rent", at(4, 5)),
        tx("may", "-1200", "Rent", at(5, 5)),
        tx("jun", "-800", "Rent", at(6, 5)),
        tx("jul", "-1000", "Rent", at(7, 5)),
        tx("aug-rent", "-770", "Rent", at(8, 5)),
        tx("aug-stream", "-30", "Streaming", at(8, 20)),
        // The cycle's last day, late: counts in August (D-01, iOS #342).
        tx("aug-last", "-600", "Car repair", at(8, 31, 18)),
        tx("groceries", "-250", "Groceries", at(9, 3)),
        tx("dining", "-150", "Dining", at(9, 4)),
        tx("transfer", "-500", "→ Holiday", at(9, 6), goalId = "goal"),
        tx("sep-stream", "-30", "Streaming", at(9, 10)),
        tx("sep-other", "-170", "Pharmacy", at(9, 12)),
    )
    private val categories = listOf(budget("Groceries", "300"), budget("Dining", "100"))

    private fun score(ignore: Boolean = false, transactions: List<FinanceTransaction> = fixture, budgets: List<FinanceCategory> = categories) =
        computeHealthScore(transactions, budgets, payCycleStartDay = 1, ignoreSubscriptions = ignore, today = today, zone = zone)

    private fun HealthScore.component(kind: HealthComponentKind) = components.single { it.kind == kind }

    @Test
    fun ac01_fixtureScores67() {
        val health = requireNotNull(score())
        assertEquals(67, health.score)
        assertEquals(HealthBand.SOLID, health.band)
        val savings = health.component(HealthComponentKind.SAVINGS)
        assertEquals(20 to 25, savings.score to savings.max)
        assertEquals(16, savings.percent)
        // iOS: rate rounded to 6 decimals, (0.2 − 0.166667) × 7200 / 6 = 39.9996 → Int 39.
        assertEquals(39, savings.monthlyGap)
        val stability = health.component(HealthComponentKind.STABILITY)
        assertEquals(12 to 25, stability.score to stability.max)
        assertEquals(25, stability.percent)
        val budget = health.component(HealthComponentKind.BUDGET)
        assertEquals(12 to 25, budget.score to budget.max)
        assertEquals(1 to 2, budget.adhering to budget.budgeted)
        val subscriptions = health.component(HealthComponentKind.SUBSCRIPTIONS)
        assertEquals(23 to 25, subscriptions.score to subscriptions.max)
        assertEquals(1, subscriptions.percent)
        health.components.forEach { assertEquals(it.kind.name, it.score < it.max, it.hasTip) }
    }

    /** D-01 is not vacuous: without the 31 Aug row August is €800 and Stability would read 14. */
    @Test
    fun ac01_lastDayOfTheCycleCounts() {
        val withoutLastDay = requireNotNull(score(transactions = fixture.filterNot { it.id == "aug-last" }))
        assertEquals(14, withoutLastDay.component(HealthComponentKind.STABILITY).score)
        assertEquals(12, requireNotNull(score()).component(HealthComponentKind.STABILITY).score)
    }

    /** iOS `recent` has no upper bound: a row after the current cycle counts in savings, not in stability. */
    @Test
    fun ac01_rowsAfterTheCurrentCycleCountOnlyInTheWindowSums() {
        val health = requireNotNull(score(transactions = fixture + tx("oct", "-100", "Rent", at(10, 2))))
        // (7200 − 6100) / 7200 = 15.28 % → Int(0.764 × 25) = 19.
        assertEquals(19, health.component(HealthComponentKind.SAVINGS).score)
        assertEquals(12, health.component(HealthComponentKind.STABILITY).score)
    }

    /** Plan r2: iOS divides in Decimal. In Double €80.16 / €100.20 is 0.1999… and would score 24. */
    @Test
    fun ac01_ratesDivideInDecimal() {
        val cents = listOf(tx("in", "100.20", "Salary", at(9, 1)), tx("out", "-80.16", "Rent", at(9, 2)))
        val savings = requireNotNull(score(transactions = cents)).component(HealthComponentKind.SAVINGS)
        assertEquals(25, savings.score)
        assertEquals(20, savings.percent)
        assertEquals(false, savings.hasTip)
    }

    @Test
    fun ac01_goalTransferChangesNothing() {
        assertEquals(score(), score(transactions = fixture.filterNot { it.goalId != null }))
    }

    @Test
    fun ac02_ignoringSubscriptionsRedistributes() {
        val health = requireNotNull(score(ignore = true))
        assertEquals(57, health.score)
        assertEquals(HealthBand.PROGRESS, health.band)
        assertEquals(
            listOf(HealthComponentKind.SAVINGS to (27 to 34), HealthComponentKind.STABILITY to (15 to 33), HealthComponentKind.BUDGET to (15 to 33)),
            health.components.map { it.kind to (it.score to it.max) },
        )
    }

    @Test
    fun ac01_bandsAndEdges() {
        assertEquals(listOf(HealthBand.ATTENTION, HealthBand.PROGRESS, HealthBand.PROGRESS, HealthBand.SOLID, HealthBand.SOLID, HealthBand.EXCELLENT),
            listOf(39, 40, 59, 60, 79, 80).map(HealthBand::of))
        assertNull("no activity in the window", score(transactions = listOf(tx("old", "-5", "Food", Instant.parse("2025-01-01T12:00:00Z")))))
        assertEquals(25, requireNotNull(score(budgets = emptyList())).component(HealthComponentKind.BUDGET).score)
        assertEquals(0 to 0, requireNotNull(score(budgets = emptyList())).component(HealthComponentKind.BUDGET).let { it.adhering to it.budgeted })
    }

    /** iOS `round()` is half away from zero: a 2 % share is (1 − 0.1333…) × 25 = 21.67 → 22, and 22.5 → 23. */
    @Test
    fun ac01_subscriptionRounding() {
        assertEquals(23, subscriptionScore(0.015))
        assertEquals(22, subscriptionScore(0.02))
        assertEquals(0, subscriptionScore(0.5))
        assertEquals(25, subscriptionScore(0.0))
    }
}
