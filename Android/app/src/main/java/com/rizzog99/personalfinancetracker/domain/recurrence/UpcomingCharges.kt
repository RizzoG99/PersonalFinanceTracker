package com.rizzog99.personalfinancetracker.domain.recurrence

import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneId

// Plan's "Coming up" (#283), from iOS `UpcomingCharge.swift` and `PlanView.swift:37-40` at b649dff.

data class UpcomingCharge(val rule: RecurrenceRule, val date: Instant)

data class UpcomingTotals(val inflow: BigDecimal, val outflow: BigDecimal)

/**
 * Every occurrence still to happen from [now] to the end of day `days - 1` (today is day 0), soonest
 * first; income included (`UpcomingCharge.swift:11-27`). Anything up to a rule's cursor already
 * happened. An auto-recorded rule's earlier-today occurrence was materialized; a forecast-only one is
 * unpaid until a payment matches it, so it stays on "today" all day.
 */
fun upcomingCharges(rules: List<RecurrenceRule>, now: Instant, zoneId: ZoneId, days: Long = 14): List<UpcomingCharge> {
    val startOfToday = now.atZone(zoneId).toLocalDate().atStartOfDay(zoneId)
    val through = startOfToday.plusDays(days).toInstant().minusSeconds(1)
    return rules.flatMap { rule ->
        val floor = if (rule.autoRecord) now else startOfToday.toInstant().minusSeconds(1)
        val since = rule.lastMaterializedDate?.let { maxOf(it, floor) } ?: floor
        RecurrenceOccurrenceCalculator.occurrences(
            frequency = rule.frequency,
            interval = rule.interval,
            startDate = rule.startDate,
            endDate = rule.endDate,
            since = since,
            through = through,
            zoneId = zoneId,
        ).map { UpcomingCharge(rule, it) }
    }.sortedBy { it.date }
}

/**
 * Money in and out, both positive (`UpcomingCharge.swift:30-36`). iOS converts to the base currency;
 * Android has no FX yet, so only [baseCurrency] rules count (#283 D-09, owner-approved) — a total
 * labelled in the base currency never mixes in another currency's amounts.
 */
fun upcomingTotals(charges: List<UpcomingCharge>, baseCurrency: String): UpcomingTotals =
    charges.filter { it.rule.currencyCode == baseCurrency }.fold(UpcomingTotals(BigDecimal.ZERO, BigDecimal.ZERO)) { sum, charge ->
        val amount = charge.rule.amount
        if (amount.signum() >= 0) sum.copy(inflow = sum.inflow + amount) else sum.copy(outflow = sum.outflow - amount)
    }

/** A rule not stopped before today (`PlanView.swift:37-40`). */
fun hasActiveRules(rules: List<RecurrenceRule>, now: Instant, zoneId: ZoneId): Boolean {
    val startOfToday = now.atZone(zoneId).toLocalDate().atStartOfDay(zoneId).toInstant()
    return rules.any { it.endDate == null || it.endDate >= startOfToday }
}
