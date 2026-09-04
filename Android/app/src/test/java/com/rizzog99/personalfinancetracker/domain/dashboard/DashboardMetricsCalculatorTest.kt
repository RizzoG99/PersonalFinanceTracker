package com.rizzog99.personalfinancetracker.domain.dashboard

import com.rizzog99.personalfinancetracker.domain.paycycle.PayCycleService
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.flow.first
import org.junit.Assert.assertEquals
import org.junit.Test

class DashboardMetricsCalculatorTest {
    private val zoneId = ZoneId.of("Europe/Rome")

    @Test
    fun `calculates signed balances and includes both financial-period boundaries`() {
        val period = PayCycleService.financialMonthContaining(
            date = java.time.LocalDate.of(2026, 2, 5),
            startDay = 10,
        )
        val metrics = DashboardMetricsCalculator.calculate(
            transactions = listOf(
                transaction("before", "2026-01-09T12:00:00Z", "100.00"),
                transaction("start", "2026-01-10T12:00:00Z", "1000.10"),
                transaction("expense", "2026-02-08T12:00:00Z", "-200.20"),
                transaction("end", "2026-02-09T12:00:00Z", "-9.70"),
            ),
            period = period,
            zoneId = zoneId,
        )

        assertEquals(BigDecimal("890.20"), metrics.totalBalance)
        assertEquals(BigDecimal("1000.10"), metrics.periodIncome)
        assertEquals(BigDecimal("209.90"), metrics.periodExpenses)
        assertEquals(listOf("end", "expense", "start", "before"), metrics.recentTransactions.map { it.id })
    }

    private fun transaction(id: String, timestamp: String, amount: String) = FinanceTransaction(
        id = id,
        timestamp = Instant.parse(timestamp),
        amount = BigDecimal(amount),
        note = "Test transaction",
        categoryLabel = "Test",
        categoryId = null,
        currencyCode = "EUR",
        goalId = null,
        recurrenceRuleId = null,
    )
}
