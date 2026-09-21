package com.rizzog99.personalfinancetracker.domain.recurrence

import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Test

class RecurrenceOccurrenceCalculatorTest {
    @Test
    fun `monthly occurrences stay anchored to the original day across short months`() {
        val occurrences = RecurrenceOccurrenceCalculator.occurrences(
            frequency = RecurrenceFrequency.MONTHLY,
            interval = 1,
            startDate = Instant.parse("2026-01-31T10:00:00Z"),
            endDate = null,
            since = null,
            through = Instant.parse("2026-03-31T10:00:00Z"),
            zoneId = ZoneOffset.UTC,
        )

        assertEquals(
            listOf(
                Instant.parse("2026-01-31T10:00:00Z"),
                Instant.parse("2026-02-28T10:00:00Z"),
                Instant.parse("2026-03-31T10:00:00Z"),
            ),
            occurrences,
        )
    }

    @Test
    fun `yearly occurrences clamp leap day in non leap years`() {
        val occurrences = RecurrenceOccurrenceCalculator.occurrences(
            frequency = RecurrenceFrequency.YEARLY,
            interval = 1,
            startDate = Instant.parse("2024-02-29T10:00:00Z"),
            endDate = null,
            since = null,
            through = Instant.parse("2026-02-28T10:00:00Z"),
            zoneId = ZoneOffset.UTC,
        )

        assertEquals(
            listOf(
                Instant.parse("2024-02-29T10:00:00Z"),
                Instant.parse("2025-02-28T10:00:00Z"),
                Instant.parse("2026-02-28T10:00:00Z"),
            ),
            occurrences,
        )
    }
}
