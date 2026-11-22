package com.rizzog99.personalfinancetracker.domain.recurrence

import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** #283 AC-02: Plan's "Coming up" timeline, ported from iOS `UpcomingCharge.timeline` at b649dff. */
class UpcomingChargesTest {
    private val zone = ZoneId.of("Europe/Rome")
    private val now = at(2026, 11, 10, 10, 0)

    private fun at(y: Int, m: Int, d: Int, h: Int = 0, min: Int = 0): Instant =
        LocalDateTime.of(y, m, d, h, min).atZone(zone).toInstant()

    private fun rule(
        id: String,
        amount: String,
        start: Instant,
        frequency: RecurrenceFrequency = RecurrenceFrequency.MONTHLY,
        lastMaterialized: Instant? = null,
        end: Instant? = null,
        autoRecord: Boolean = true,
    ) = RecurrenceRule(
        id = id,
        frequency = frequency,
        interval = 1,
        startDate = start,
        endDate = end,
        lastMaterializedDate = lastMaterialized,
        amount = BigDecimal(amount),
        note = id,
        categoryLabel = "",
        categoryId = null,
        currencyCode = "EUR",
        goalId = null,
        autoRecord = autoRecord,
    )

    private val rules = listOf(
        rule("Netflix", "-13.00", at(2026, 10, 14), lastMaterialized = at(2026, 10, 14)),
        // Auto-recorded: today's 09:00 occurrence already happened (floor = now), 11-24 is past the window.
        rule("Gym", "-30.00", at(2026, 11, 3, 9), RecurrenceFrequency.WEEKLY, lastMaterialized = at(2026, 11, 3, 9)),
        // Forecast-only: unpaid until a payment matches, so today's 08:00 stays (floor = start of today - 1 s).
        rule("Rent", "-800.00", at(2026, 10, 10, 8), lastMaterialized = at(2026, 10, 10, 8), autoRecord = false),
        rule("Salary", "1500.00", at(2026, 10, 27), lastMaterialized = at(2026, 10, 27)),
        rule("Stopped", "-5.00", at(2026, 11, 1), RecurrenceFrequency.WEEKLY, end = at(2026, 11, 12)),
        rule("Bonus", "200.00", at(2026, 11, 20)),
    )

    @Test
    fun ac02_timelineKeepsTheNext14DaysSoonestFirst() {
        val charges = upcomingCharges(rules, now, zone)

        assertEquals(
            listOf(
                "Rent" to at(2026, 11, 10, 8),
                "Netflix" to at(2026, 11, 14),
                "Gym" to at(2026, 11, 17, 9),
                "Bonus" to at(2026, 11, 20),
            ),
            charges.map { it.rule.id to it.date },
        )
    }

    @Test
    fun ac02_totalsSplitMoneyInAndOut() {
        val totals = upcomingTotals(upcomingCharges(rules, now, zone), baseCurrency = "EUR")

        assertEquals(BigDecimal("200.00"), totals.inflow)
        assertEquals(BigDecimal("843.00"), totals.outflow)
    }

    @Test
    fun ac02_d09TotalsCountOnlyTheBaseCurrencyButEveryRowStays() {
        val mixed = rules + rule("Spotify", "-9.99", at(2026, 11, 12)).copy(currencyCode = "USD")
        val charges = upcomingCharges(mixed, now, zone)

        assertEquals(5, charges.size)
        assertEquals(UpcomingTotals(BigDecimal("200.00"), BigDecimal("843.00")), upcomingTotals(charges, "EUR"))
        assertEquals(UpcomingTotals(BigDecimal.ZERO, BigDecimal("9.99")), upcomingTotals(charges, "USD"))
    }

    @Test
    fun ac03_aRuleStoppedBeforeTodayIsNotActive() {
        val stoppedYesterday = rule("Old", "-5.00", at(2026, 1, 1), end = at(2026, 11, 9, 23))
        val endsToday = rule("Today", "-5.00", at(2026, 1, 1), end = at(2026, 11, 10))

        assertFalse(hasActiveRules(listOf(stoppedYesterday), now, zone))
        assertTrue(hasActiveRules(listOf(stoppedYesterday, endsToday), now, zone))
    }
}
