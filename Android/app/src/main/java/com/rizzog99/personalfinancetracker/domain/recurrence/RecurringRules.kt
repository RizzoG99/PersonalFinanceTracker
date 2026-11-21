package com.rizzog99.personalfinancetracker.domain.recurrence

import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneId

// #294 red baseline (D-08): typed no-op stubs so the AC tests compile and fail on assertions.

fun RecurrenceRule.isActive(now: Instant): Boolean = true

fun RecurrenceRule.monthlyEquivalent(): BigDecimal = BigDecimal.ZERO

fun monthlySpend(active: List<RecurrenceRule>): BigDecimal = BigDecimal.ZERO

fun duplicateRuleIds(active: List<RecurrenceRule>): Set<String> = emptySet()

fun RecurrenceRule.title(): String = note

fun RecurrenceRule.nextOccurrence(now: Instant, zoneId: ZoneId): Instant? = null
