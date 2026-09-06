package com.rizzog99.personalfinancetracker.domain.recurrence

import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

object RecurrenceOccurrenceCalculator {
    fun occurrences(
        frequency: RecurrenceFrequency,
        interval: Int,
        startDate: Instant,
        endDate: Instant?,
        since: Instant?,
        through: Instant,
        zoneId: ZoneId,
    ): List<Instant> {
        require(interval > 0)
        val cutoff = minOf(endDate ?: through, through)
        if (startDate > cutoff) return emptyList()
        val anchor = startDate.atZone(zoneId)
        val result = mutableListOf<Instant>()
        var index = 0L
        while (index < 10_000) {
            val occurrence = when (frequency) {
                RecurrenceFrequency.WEEKLY -> anchor.plusWeeks(index * interval)
                RecurrenceFrequency.MONTHLY -> anchor.withClampedMonthOffset(index * interval)
                RecurrenceFrequency.YEARLY -> anchor.withClampedMonthOffset(index * interval * 12)
            }.toInstant()
            if (occurrence > cutoff) break
            if (since == null || occurrence > since) result += occurrence
            index++
        }
        return result
    }

    private fun java.time.ZonedDateTime.withClampedMonthOffset(months: Long): java.time.ZonedDateTime {
        val targetMonth = YearMonth.from(this).plusMonths(months)
        return withYear(targetMonth.year).withMonth(targetMonth.monthValue).withDayOfMonth(
            minOf(dayOfMonth, targetMonth.lengthOfMonth()),
        )
    }
}
