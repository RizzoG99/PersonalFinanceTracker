package com.rizzog99.personalfinancetracker.domain.insights

import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale

/** The zone and first weekday the explorer's calendar periods are cut with (iOS `Calendar.current`). */
data class ExplorerCalendar(val zone: ZoneId, val firstDayOfWeek: DayOfWeek) {
    fun date(instant: Instant): LocalDate = instant.atZone(zone).toLocalDate()
    fun startOf(day: LocalDate): Instant = day.atStartOfDay(zone).toInstant()

    companion object {
        fun of(zone: ZoneId, locale: Locale = Locale.getDefault()) = ExplorerCalendar(zone, WeekFields.of(locale).firstDayOfWeek)
    }
}

enum class ExplorerGranularity { WEEK, MONTH, YEAR, CUSTOM }

/** End-exclusive. */
data class TimeRange(val start: Instant, val end: Instant)

/**
 * The Insights explorer's period (#303): a calendar week / month / year, or a custom range of whole
 * days, that ‹ › step through. Calendar-based on purpose, unlike Health Score's pay cycle. Port of
 * iOS `ExplorerPeriod.swift` at b649dff.
 */
data class ExplorerPeriod(val granularity: ExplorerGranularity, val start: Instant, val end: Instant) {

    fun previous(calendar: ExplorerCalendar) = shifted(-1, calendar)
    fun next(calendar: ExplorerCalendar) = shifted(1, calendar)

    /** While `now` is inside the period, › is disabled (no future periods). */
    fun isCurrent(now: Instant) = end > now

    /** Re-anchors on this period's start, so Sep 2025 → Year shows 2025 (iOS `BreakdownExplorerSection.swift:94`). */
    fun withGranularity(granularity: ExplorerGranularity, calendar: ExplorerCalendar) = current(granularity, start, calendar)

    fun days(calendar: ExplorerCalendar): Long = ChronoUnit.DAYS.between(calendar.date(start), calendar.date(end))

    /**
     * What Δ compares against: the whole previous period once this one is over; while it runs, only
     * the same elapsed stretch of the previous one, clamped to its end (on 31 Mar: all of February).
     */
    fun comparisonInterval(now: Instant, calendar: ExplorerCalendar): TimeRange {
        val previous = previous(calendar)
        if (now < start || now >= end) return TimeRange(previous.start, previous.end)
        val elapsed = Duration.between(start, now)
        return TimeRange(previous.start, minOf(previous.end, previous.start + elapsed))
    }

    private fun shifted(value: Long, calendar: ExplorerCalendar): ExplorerPeriod {
        val from = start.atZone(calendar.zone)
        return when (granularity) {
            ExplorerGranularity.CUSTOM -> {
                val days = days(calendar)
                val first = calendar.date(start).plusDays(value * days)
                ExplorerPeriod(granularity, calendar.startOf(first), calendar.startOf(first.plusDays(days)))
            }
            ExplorerGranularity.WEEK -> current(granularity, from.plusWeeks(value).toInstant(), calendar)
            ExplorerGranularity.MONTH -> current(granularity, from.plusMonths(value).toInstant(), calendar)
            ExplorerGranularity.YEAR -> current(granularity, from.plusYears(value).toInstant(), calendar)
        }
    }

    companion object {
        /** The calendar week / month / year containing [now]; CUSTOM falls back to the month. */
        fun current(granularity: ExplorerGranularity, now: Instant, calendar: ExplorerCalendar): ExplorerPeriod {
            val day = calendar.date(now)
            val (first, last) = when (granularity) {
                ExplorerGranularity.WEEK -> day.with(TemporalAdjusters.previousOrSame(calendar.firstDayOfWeek)).let { it to it.plusWeeks(1) }
                ExplorerGranularity.YEAR -> day.withDayOfYear(1).let { it to it.plusYears(1) }
                ExplorerGranularity.MONTH, ExplorerGranularity.CUSTOM -> day.withDayOfMonth(1).let { it to it.plusMonths(1) }
            }
            val resolved = if (granularity == ExplorerGranularity.CUSTOM) ExplorerGranularity.MONTH else granularity
            return ExplorerPeriod(resolved, calendar.startOf(first), calendar.startOf(last))
        }

        /** Whole days from [from]'s day through [through]'s day, both included, in either order. */
        fun custom(from: LocalDate, through: LocalDate, calendar: ExplorerCalendar): ExplorerPeriod {
            val first = minOf(from, through)
            val last = maxOf(from, through)
            return ExplorerPeriod(ExplorerGranularity.CUSTOM, calendar.startOf(first), calendar.startOf(last.plusDays(1)))
        }
    }
}

/** ‹ is offered only while the previous period still overlaps recorded history (iOS `InsightsViewModel.swift:60-63`). */
fun canGoPrevious(period: ExplorerPeriod, firstTransaction: Instant?, calendar: ExplorerCalendar): Boolean =
    firstTransaction != null && period.previous(calendar).end > firstTransaction

/** Selectable days of the custom-range picker, and its initial selection (iOS `CustomRangeSheet` init). */
data class CustomRangeBounds(val earliest: LocalDate, val latest: LocalDate, val initialFrom: LocalDate, val initialTo: LocalDate)

fun customRangeBounds(firstTransaction: Instant?, now: Instant, period: ExplorerPeriod, calendar: ExplorerCalendar): CustomRangeBounds {
    val today = calendar.date(now)
    val earliest = calendar.date(minOf(firstTransaction ?: now, now))
    val lastIncluded = calendar.date(period.end).minusDays(1)
    val to = lastIncluded.coerceIn(earliest, today)
    val from = calendar.date(period.start).coerceIn(earliest, to)
    return CustomRangeBounds(earliest, today, from, to)
}
