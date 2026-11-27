package com.rizzog99.personalfinancetracker.domain.dashboard

import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * #298, ported from iOS `SafeToSpendSnapshotBuilderTests` / `SafeToSpendSnapshotTests` at b649dff:
 * pay cycle starts on the 27th; "today" is 7 Oct 2026, so the cycle is 27 Sep – 26 Oct.
 */
class SafeToSpendCalculatorTest {
    private val zone = ZoneId.of("Europe/Rome")

    private fun at(month: Int, day: Int, hour: Int = 12, minute: Int = 0): Instant =
        LocalDateTime.of(2026, month, day, hour, minute).atZone(zone).toInstant()

    private var ids = 0

    private fun tx(time: Instant, amount: String, goalId: String? = null, currency: String = "EUR") = FinanceTransaction(
        id = "t${ids++}", timestamp = time, amount = BigDecimal(amount), note = "", categoryLabel = "",
        categoryId = null, currencyCode = currency, goalId = goalId, recurrenceRuleId = null,
    )

    private fun rule(
        start: Instant,
        amount: String,
        cursor: Instant? = null,
        autoRecord: Boolean = true,
        goalId: String? = null,
        endDate: Instant? = null,
        currency: String = "EUR",
    ) = RecurrenceRule(
        id = "r${ids++}", frequency = RecurrenceFrequency.MONTHLY, interval = 1, startDate = start, endDate = endDate,
        lastMaterializedDate = cursor, amount = BigDecimal(amount), note = "", categoryLabel = "", categoryId = null,
        currencyCode = currency, goalId = goalId, autoRecord = autoRecord,
    )

    private fun compute(
        transactions: List<FinanceTransaction> = emptyList(),
        rules: List<RecurrenceRule> = emptyList(),
        buffer: Int = 5,
        now: Instant = at(10, 7),
    ) = SafeToSpendCalculator.compute(transactions, rules, payCycleStartDay = 27, bufferPercent = buffer, baseCurrency = "EUR", now = now, zoneId = zone)

    private val salary get() = tx(at(9, 27), "2000")

    private fun assertMoney(expected: String, actual: BigDecimal) =
        assertEquals("expected $expected, was $actual", 0, BigDecimal(expected).compareTo(actual))

    @Test
    fun ac01_recordedIncomeMinusSpentMinusBuffer() {
        val safe = compute(listOf(salary, tx(at(10, 1), "-600")))

        assertMoney("2000", safe.income)
        assertMoney("600", safe.spent)
        assertMoney("100", safe.buffer)
        assertMoney("1300", safe.amount)
        assertEquals(LocalDate.of(2026, 9, 27), safe.cycleStart)
        assertEquals(LocalDate.of(2026, 10, 27), safe.payday)
    }

    @Test
    fun ac01_zeroBufferReservesNothing() {
        assertMoney("2000", compute(listOf(salary), buffer = 0).amount)
    }

    @Test
    fun ac02_salaryRuleStillDueThisCycleCountsAsIncome() {
        // New cycle started on the 27th, salary lands on the 28th.
        val salaryRule = rule(start = at(9, 28), cursor = at(9, 28), amount = "2000")
        val safe = compute(rules = listOf(salaryRule), buffer = 0, now = at(10, 27, 9))

        assertMoney("2000", safe.income)
    }

    @Test
    fun ac02_occurrenceOnOrAfterPaydayIsNotReserved() {
        assertMoney("0", compute(listOf(salary), rules = listOf(rule(start = at(10, 27), amount = "-400"))).recurring)
    }

    @Test
    fun ac02_ruleEndedBeforeTodayIsNotActive() {
        val ended = rule(start = at(9, 20), amount = "-400", endDate = at(10, 1))
        assertMoney("0", compute(listOf(salary), rules = listOf(ended)).recurring)
    }

    @Test
    fun ac03_goalTransfersAreCountedOnceUnderGoals() {
        val goal = rule(start = at(10, 15), amount = "-100", goalId = "trip")
        val rent = rule(start = at(10, 20), amount = "-400")
        val safe = compute(listOf(salary), rules = listOf(goal, rent))

        assertMoney("100", safe.goals)
        assertMoney("400", safe.recurring)
        assertMoney("1400", safe.amount)
    }

    @Test
    fun ac03_recordedGoalTransferIsSpentNotGoals() {
        // iOS's transaction loop has no goalId filter: money already moved to a goal left the account.
        val safe = compute(listOf(salary, tx(at(10, 2), "-150", goalId = "trip")))

        assertMoney("150", safe.spent)
        assertMoney("0", safe.goals)
    }

    @Test
    fun ac04_forecastOnlyRuleAlreadyMatchedIsNotReservedAgain() {
        // Paid early: the matched payment moved the cursor onto this cycle's occurrence.
        val paid = rule(start = at(10, 10), cursor = at(10, 10), autoRecord = false, amount = "-240")
        val unpaid = rule(start = at(10, 10), autoRecord = false, amount = "-240")

        assertMoney("0", compute(listOf(salary), rules = listOf(paid)).recurring)
        assertMoney("240", compute(listOf(salary), rules = listOf(unpaid)).recurring)
    }

    @Test
    fun ac05_lastDayOfTheCycleIsInsideNextPaydayIsNot() {
        val lastDay = tx(at(10, 26, 23, 30), "-50")
        val payday = tx(at(10, 27, 0, 0), "-70")

        assertMoney("50", compute(listOf(salary, lastDay, payday), now = at(10, 26)).spent)
    }

    @Test
    fun ac06_perDaySpreadsOverTheDaysLeftIncludingToday() {
        val today = LocalDate.of(2026, 10, 7)
        val payday = today.plusDays(20)
        assertMoney("30", SafeToSpendCalculator.perDay(BigDecimal("600"), today, payday)!!)
        assertMoney("60", SafeToSpendCalculator.perDay(BigDecimal("600"), today.plusDays(10), payday)!!)
    }

    @Test
    fun ac06_perDayRoundsDownAndNeverThrows() {
        val today = LocalDate.of(2026, 10, 7)
        // €467.16 over 3 days is €155.72 — "€156/day" would add up to €468.
        assertMoney("155", SafeToSpendCalculator.perDay(BigDecimal("467.16"), today, today.plusDays(3))!!)
        // A non-terminating quotient must not throw ArithmeticException.
        assertMoney("192", SafeToSpendCalculator.perDay(BigDecimal("1345"), today, today.plusDays(7))!!)
    }

    @Test
    fun ac06_noPerDayFigureWhenNothingLeftOrPaydayArrived() {
        val today = LocalDate.of(2026, 10, 7)
        assertNull(SafeToSpendCalculator.perDay(BigDecimal("-150"), today, today.plusDays(20)))
        assertNull(SafeToSpendCalculator.perDay(BigDecimal.ZERO, today, today.plusDays(20)))
        assertNull(SafeToSpendCalculator.perDay(BigDecimal("600"), today, today))
    }

    @Test
    fun ac06_lastCoveredDayIsTheDayBeforePayday() {
        assertEquals(LocalDate.of(2026, 10, 26), SafeToSpendCalculator.lastDay(LocalDate.of(2026, 10, 27)))
    }

    @Test
    fun ac07_overspendingGoesNegativeOverPlan() {
        val safe = compute(listOf(salary, tx(at(10, 2), "-2050")))

        assertMoney("-150", safe.amount)
        assertEquals(SafeToSpendStanding.OVER_PLAN, safe.standing)
        assertNull(SafeToSpendCalculator.perDay(safe.amount, LocalDate.of(2026, 10, 7), safe.payday))
    }

    @Test
    fun ac07_standingUsesTheBufferAsACushion() {
        assertEquals(SafeToSpendStanding.WITHIN_PLAN, safeToSpendStanding(BigDecimal.ZERO, BigDecimal("100")))
        assertEquals(SafeToSpendStanding.USING_BUFFER, safeToSpendStanding(BigDecimal("-50"), BigDecimal("100")))
        assertEquals(SafeToSpendStanding.USING_BUFFER, safeToSpendStanding(BigDecimal("-100"), BigDecimal("100")))
        assertEquals(SafeToSpendStanding.OVER_PLAN, safeToSpendStanding(BigDecimal("-150"), BigDecimal("100")))
    }

    @Test
    fun ac09_cycleWithNoIncomeHasZeroIncome() {
        val safe = compute(listOf(tx(at(10, 2), "-300")))

        assertMoney("0", safe.income)
        assertMoney("300", safe.spent)
    }

    @Test
    fun ac13_otherCurrenciesDoNotCount() {
        val usdRow = tx(at(10, 2), "-500", currency = "USD")
        val usdRule = rule(start = at(10, 20), amount = "-400", currency = "USD")
        val usdIncome = tx(at(10, 3), "900", currency = "USD")

        assertMoney("1900", compute(listOf(salary, usdRow, usdIncome), rules = listOf(usdRule)).amount)
    }
}
