package com.rizzog99.personalfinancetracker.domain.paycycle

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PayCycleServiceTest {
    @Test
    fun `finds the current-month start when the reference date reaches the start day`() {
        val period = PayCycleService.financialMonthContaining(LocalDate.of(2026, 1, 15), startDay = 10)

        assertEquals(LocalDate.of(2026, 1, 10), period.start)
        assertEquals(LocalDate.of(2026, 2, 9), period.endInclusive)
    }

    @Test
    fun `finds the prior-month start before the start day`() {
        val period = PayCycleService.financialMonthContaining(LocalDate.of(2026, 1, 5), startDay = 10)

        assertEquals(LocalDate.of(2025, 12, 10), period.start)
        assertEquals(LocalDate.of(2026, 1, 9), period.endInclusive)
    }

    @Test
    fun `returns financial months in ascending order with the reference date in the last period`() {
        val referenceDate = LocalDate.of(2026, 1, 15)
        val periods = PayCycleService.financialMonths(count = 3, before = referenceDate, startDay = 10)

        assertEquals(3, periods.size)
        assertTrue(periods.zipWithNext().all { (first, second) -> first.start.isBefore(second.start) })
        assertTrue(referenceDate in periods.last())
    }
}
