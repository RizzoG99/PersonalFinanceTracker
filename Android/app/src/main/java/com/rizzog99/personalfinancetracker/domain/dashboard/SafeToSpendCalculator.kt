package com.rizzog99.personalfinancetracker.domain.dashboard

import com.rizzog99.personalfinancetracker.domain.paycycle.PayCycleService
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.upcomingCharges
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Where Safe to Spend stands (iOS #260, `SafeToSpendSnapshot.standing` on main): the buffer is a
 * cushion the user chose, not a limit — spending into it warns, only going past it is over plan.
 */
enum class SafeToSpendStanding { WITHIN_PLAN, USING_BUFFER, OVER_PLAN }

fun safeToSpendStanding(amount: BigDecimal, buffer: BigDecimal): SafeToSpendStanding = when {
    amount.signum() >= 0 -> SafeToSpendStanding.WITHIN_PLAN
    (amount + buffer).signum() >= 0 -> SafeToSpendStanding.USING_BUFFER
    else -> SafeToSpendStanding.OVER_PLAN
}

/** Safe to Spend until payday (#298, iOS `SafeToSpend` at b649dff). Every part is positive. */
data class SafeToSpend(
    /** Recorded this cycle plus recurring income still due before payday. */
    val income: BigDecimal,
    val spent: BigDecimal,
    /** Recurring expenses still due before payday, goal transfers excluded. */
    val recurring: BigDecimal,
    /** Recurring goal transfers still due before payday. */
    val goals: BigDecimal,
    val buffer: BigDecimal,
    val cycleStart: LocalDate,
    /** Start of the next cycle: the amount covers every day before it. */
    val payday: LocalDate,
) {
    val amount: BigDecimal get() = income - spent - recurring - goals - buffer
    val standing: SafeToSpendStanding get() = safeToSpendStanding(amount, buffer)
}

/** Port of iOS `SafeToSpendSnapshotBuilder.compute` (`Utilities/SafeToSpendSnapshotBuilder.swift` at b649dff). */
object SafeToSpendCalculator {
    fun compute(
        transactions: List<FinanceTransaction>,
        rules: List<RecurrenceRule>,
        payCycleStartDay: Int,
        bufferPercent: Int,
        baseCurrency: String,
        now: Instant,
        zoneId: ZoneId,
    ): SafeToSpend {
        val today = now.atZone(zoneId).toLocalDate()
        val cycle = PayCycleService.financialMonthContaining(today, payCycleStartDay)
        val payday = cycle.endInclusive.plusDays(1)

        var income = BigDecimal.ZERO
        var spent = BigDecimal.ZERO
        var recurring = BigDecimal.ZERO
        var goals = BigDecimal.ZERO
        // ponytail: base currency only (D-01, as #283 D-09) — Android has no FX to convert the rest.
        // Recorded goal transfers land in `spent`: iOS's loop has no goalId filter, the money left.
        for (transaction in transactions) {
            if (transaction.currencyCode != baseCurrency) continue
            if (transaction.timestamp.atZone(zoneId).toLocalDate() !in cycle) continue
            if (transaction.amount.signum() > 0) income += transaction.amount else spent -= transaction.amount
        }
        // Active as iOS `isActive(asOf: startOfToday)`; the timeline already skips what a cursor marks paid.
        val startOfToday = today.atStartOfDay(zoneId).toInstant()
        val active = rules.filter { it.currencyCode == baseCurrency && (it.endDate == null || it.endDate >= startOfToday) }
        for (charge in upcomingCharges(active, now, zoneId, days = daysLeft(today, payday))) {
            val amount = charge.rule.amount
            when {
                amount.signum() > 0 -> income += amount
                charge.rule.goalId != null -> goals -= amount
                else -> recurring -= amount
            }
        }
        return SafeToSpend(
            income = income, spent = spent, recurring = recurring, goals = goals,
            // Exact, like iOS Decimal: Kotlin's `/` would round to the dividend's scale.
            buffer = income.multiply(BigDecimal(bufferPercent)).movePointLeft(2),
            cycleStart = cycle.start, payday = payday,
        )
    }

    /** Days from [today] up to the day before [payday], counting today; 0 once payday arrives. */
    fun daysLeft(today: LocalDate, payday: LocalDate): Long = maxOf(0, ChronoUnit.DAYS.between(today, payday))

    /**
     * The per-day figure in whole units, only while there is something left to spread. Rounded down:
     * "€156/day" for €467 over 3 days would promise more than there is.
     */
    fun perDay(amount: BigDecimal, today: LocalDate, payday: LocalDate): BigDecimal? {
        val days = daysLeft(today, payday)
        if (amount.signum() <= 0 || days == 0L) return null
        return amount.divide(BigDecimal(days), 0, RoundingMode.DOWN)
    }

    /** The last day the amount covers — "until 26 Oct" reads inclusive; payday itself isn't covered. */
    fun lastDay(payday: LocalDate): LocalDate = payday.minusDays(1)
}
