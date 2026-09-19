package com.rizzog99.personalfinancetracker.domain.insight

import java.math.BigDecimal
import java.time.Instant

/** One dated financial-health reading. Mirrors the frozen `HealthScoreSnapshot`. */
data class HealthScoreSnapshot(
    val id: String,
    val timestamp: Instant,
    val score: Int,
    val savingsScore: Int,
    val stabilityScore: Int,
    val adherenceScore: Int,
    val subscriptionScore: Int,
)

/**
 * The cumulative month-to-date spend curve, cached so the Insights tab does not recompute it on
 * every appearance. Mirrors the frozen `DailyForecastCache`, which is a singleton: saving a new
 * month replaces the previous row rather than accumulating history.
 *
 * The frozen model stores `amounts: [Double]`. Android keeps exact `BigDecimal` instead — money
 * never touches binary floating point here — so this is a deliberate, narrower encoding.
 */
data class DailyForecastCache(
    val monthKey: String,
    val computedUpToDay: Int,
    val dayValues: List<DayValue>,
)

data class DayValue(val day: Int, val amount: BigDecimal)
