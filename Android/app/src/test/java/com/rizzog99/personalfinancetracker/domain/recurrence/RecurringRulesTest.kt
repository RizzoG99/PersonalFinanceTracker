package com.rizzog99.personalfinancetracker.domain.recurrence

import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** #294 AC-01: the Recurring screen's numbers (iOS `RecurringView.swift` at b649dff). */
class RecurringRulesTest {
    private val zone = ZoneId.of("Europe/Rome")
    private val now = Instant.parse("2026-11-21T11:00:00Z")

    private fun rule(
        id: String,
        note: String,
        amount: String,
        start: String,
        frequency: RecurrenceFrequency = RecurrenceFrequency.MONTHLY,
        interval: Int = 1,
        end: String? = null,
        category: String = "Bills",
    ) = RecurrenceRule(
        id = id, frequency = frequency, interval = interval,
        startDate = LocalDate.parse(start).atTime(10, 0).atZone(zone).toInstant(),
        endDate = end?.let(Instant::parse), lastMaterializedDate = null, amount = BigDecimal(amount),
        note = note, categoryLabel = category, categoryId = null, currencyCode = "EUR", goalId = null,
    )

    private val netflix = rule("n", "Netflix", "-12.99", "2026-01-05", category = "Entertainment")
    private val salary = rule("s", "Salary", "2000.00", "2026-01-27")
    private val gym = rule("g", "Gym", "-30.00", "2026-11-10", RecurrenceFrequency.WEEKLY, interval = 2)

    @Test
    fun ac01_monthlySpendCountsExpenseRulesOnly() {
        // 12.99 + 30 × 52 / 12 / 2 = 77.99; the salary is not a commitment.
        assertEquals(BigDecimal("-77.99"), monthlySpend(listOf(netflix, salary, gym)))
        assertEquals(0, BigDecimal("-2.50").compareTo(rule("y", "Domain", "-30", "2026-03-01", RecurrenceFrequency.YEARLY).monthlyEquivalent()))
    }

    @Test
    fun ac01_nextOccurrenceIsTheFirstFromNowWithinAYear() {
        assertEquals(LocalDate.parse("2026-12-05"), netflix.nextOccurrence(now, zone)?.atZone(zone)?.toLocalDate())
        assertEquals(LocalDate.parse("2026-11-27"), salary.nextOccurrence(now, zone)?.atZone(zone)?.toLocalDate())
        assertEquals(LocalDate.parse("2026-11-24"), gym.nextOccurrence(now, zone)?.atZone(zone)?.toLocalDate())
        assertNull(rule("f", "Far", "-1", "2028-01-01").nextOccurrence(now, zone))
    }

    @Test
    fun ac01_sameTitleAndCadenceIsAPossibleDuplicate() {
        val twin = rule("n2", "netflix", "-15.99", "2026-02-10")
        val yearly = rule("n3", "Netflix", "-120", "2026-02-10", RecurrenceFrequency.YEARLY)
        assertEquals(setOf("n", "n2"), duplicateRuleIds(listOf(netflix, twin, yearly, gym)))
    }

    @Test
    fun ac03_aRuleEndedBeforeNowIsNotActive() {
        assertTrue(netflix.isActive(now))
        assertTrue(netflix.copy(endDate = now).isActive(now))
        assertFalse(netflix.copy(endDate = now.minusSeconds(1)).isActive(now))
    }

    @Test
    fun ac01_titleFallsBackToTheCategoryWithoutItsEmoji() {
        assertEquals("Netflix", netflix.title())
        assertEquals("Entertainment", netflix.copy(note = "", categoryLabel = "🎬 Entertainment").title())
    }
}
