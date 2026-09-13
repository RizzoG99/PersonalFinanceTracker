package com.rizzog99.personalfinancetracker.domain.pulse

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Test

class FinancialPulseCalculatorTest {
    private val zoneId = ZoneId.of("UTC")

    @Test
    fun testNoTransactions() {
        val now = Instant.parse("2026-09-13T12:00:00Z")
        val transactions = emptyList<FinanceTransaction>()

        val result = FinancialPulseCalculator.calculate(transactions, now, zoneId)

        assertEquals(0, result.todayTransactionCount)
        assertEquals(0, result.streakDays)
    }

    @Test
    fun testTodayHasOneTransaction() {
        val now = Instant.parse("2026-09-13T12:00:00Z")
        val today = LocalDate.ofInstant(now, zoneId)

        val transaction = FinanceTransaction(
            id = "1",
            timestamp = today.atTime(10, 0).atZone(zoneId).toInstant(),
            amount = BigDecimal("100.00"),
            note = "Test",
            categoryLabel = "Test",
            categoryId = null,
            currencyCode = "EUR",
            goalId = null,
            recurrenceRuleId = null,
        )

        val result = FinancialPulseCalculator.calculate(listOf(transaction), now, zoneId)

        assertEquals(1, result.todayTransactionCount)
        assertEquals(1, result.streakDays)
    }

    @Test
    fun testThreeDayStreak() {
        val now = Instant.parse("2026-09-13T12:00:00Z")
        val today = LocalDate.ofInstant(now, zoneId)

        val transactions = listOf(
            createTransaction("1", today.minusDays(2)),
            createTransaction("2", today.minusDays(1)),
            createTransaction("3", today),
        )

        val result = FinancialPulseCalculator.calculate(transactions, now, zoneId)

        assertEquals(1, result.todayTransactionCount)
        assertEquals(3, result.streakDays)
    }

    @Test
    fun testStreakBrokenByGap() {
        val now = Instant.parse("2026-09-13T12:00:00Z")
        val today = LocalDate.ofInstant(now, zoneId)

        val transactions = listOf(
            createTransaction("1", today.minusDays(3)),
            createTransaction("2", today.minusDays(2)), // Gap on day-1
            createTransaction("3", today),
        )

        val result = FinancialPulseCalculator.calculate(transactions, now, zoneId)

        // Streak should be just 1 day (today), because yesterday has no transaction
        assertEquals(1, result.todayTransactionCount)
        assertEquals(1, result.streakDays)
    }

    @Test
    fun testTodayWithoutTransactionsYesterdayWithoutBreak() {
        val now = Instant.parse("2026-09-13T12:00:00Z")
        val today = LocalDate.ofInstant(now, zoneId)

        val transactions = listOf(
            createTransaction("1", today.minusDays(2)),
            createTransaction("2", today.minusDays(1)),
            // Today has no transaction
        )

        val result = FinancialPulseCalculator.calculate(transactions, now, zoneId)

        assertEquals(0, result.todayTransactionCount)
        // Streak should include yesterday (no gap)
        assertEquals(2, result.streakDays)
    }

    private fun createTransaction(id: String, date: LocalDate): FinanceTransaction {
        return FinanceTransaction(
            id = id,
            timestamp = date.atTime(10, 0).atZone(zoneId).toInstant(),
            amount = BigDecimal("100.00"),
            note = "Test",
            categoryLabel = "Test",
            categoryId = null,
            currencyCode = "EUR",
            goalId = null,
            recurrenceRuleId = null,
        )
    }
}
