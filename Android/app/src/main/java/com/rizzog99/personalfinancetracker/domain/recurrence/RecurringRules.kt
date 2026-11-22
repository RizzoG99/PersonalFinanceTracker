package com.rizzog99.personalfinancetracker.domain.recurrence

import com.rizzog99.personalfinancetracker.domain.import.removingLeadingEmoji
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.time.Instant
import java.time.ZoneId

// The Recurring screen's rules (#294), from iOS `RecurringView.swift` at b649dff.

/** Not stopped before [now] (`RecurringView.swift:156-158`). */
fun RecurrenceRule.isActive(now: Instant): Boolean = endDate == null || endDate >= now

/** The amount spread over one month, sign kept (`GoalProjection.swift:121-130`). */
fun RecurrenceRule.monthlyEquivalent(): BigDecimal {
    val perCycle = amount.divide(BigDecimal(interval), MathContext.DECIMAL64)
    return when (frequency) {
        RecurrenceFrequency.MONTHLY -> perCycle
        RecurrenceFrequency.WEEKLY -> perCycle.multiply(BigDecimal(52)).divide(BigDecimal(12), MathContext.DECIMAL64)
        RecurrenceFrequency.YEARLY -> perCycle.divide(BigDecimal(12), MathContext.DECIMAL64)
    }
}

/** Expense rules only, negative: what recurring spend the user is locked into (`RecurringView.swift:171-175`). */
fun monthlySpend(active: List<RecurrenceRule>): BigDecimal =
    active.filter { it.amount.signum() < 0 }
        .fold(BigDecimal.ZERO) { sum, rule -> sum + rule.monthlyEquivalent() }
        .setScale(2, RoundingMode.HALF_EVEN)

/** Same title and cadence among active rules: one series detected twice, flagged not merged (`:163-166`). */
fun duplicateRuleIds(active: List<RecurrenceRule>): Set<String> =
    active.groupBy { "${it.title().lowercase()}#${it.frequency}#${it.interval}" }
        .values.filter { it.size > 1 }.flatten().map { it.id }.toSet()

/** The name, or the category without its emoji (`FixedExpensesSection.swift:10-12`). */
fun RecurrenceRule.title(): String = note.ifBlank { categoryLabel.removingLeadingEmoji().trim() }

/** The first occurrence after [now] within a year (`RecurringView.swift:298-306`). */
fun RecurrenceRule.nextOccurrence(now: Instant, zoneId: ZoneId): Instant? =
    RecurrenceOccurrenceCalculator.occurrences(
        frequency = frequency,
        interval = interval,
        startDate = startDate,
        endDate = endDate,
        since = now,
        through = now.atZone(zoneId).plusYears(1).toInstant(),
        zoneId = zoneId,
    ).firstOrNull()
