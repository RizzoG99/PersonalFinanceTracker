package com.rizzog99.personalfinancetracker.domain.paycycle

import java.time.Clock
import java.time.LocalDate

data class FinancialPeriod(
    val start: LocalDate,
    val endInclusive: LocalDate,
) {
    init {
        require(!endInclusive.isBefore(start))
    }

    operator fun contains(date: LocalDate): Boolean = !date.isBefore(start) && !date.isAfter(endInclusive)
}

object PayCycleService {
    fun financialMonthContaining(date: LocalDate, startDay: Int): FinancialPeriod {
        require(startDay in 1..28) { "Pay-cycle start day must be between 1 and 28." }
        val start = if (date.dayOfMonth >= startDay) {
            date.withDayOfMonth(startDay)
        } else {
            date.minusMonths(1).withDayOfMonth(startDay)
        }
        return FinancialPeriod(start = start, endInclusive = start.plusMonths(1).minusDays(1))
    }

    fun currentFinancialMonth(startDay: Int, clock: Clock = Clock.systemDefaultZone()): FinancialPeriod =
        financialMonthContaining(LocalDate.now(clock), startDay)

    fun financialMonths(count: Int, before: LocalDate, startDay: Int): List<FinancialPeriod> {
        require(count >= 0) { "Financial month count cannot be negative." }
        var date = before
        return buildList {
            repeat(count) {
                val period = financialMonthContaining(date, startDay)
                add(period)
                date = period.start.minusDays(1)
            }
        }.asReversed()
    }
}
