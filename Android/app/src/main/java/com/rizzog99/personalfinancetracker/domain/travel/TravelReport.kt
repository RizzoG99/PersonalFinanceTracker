package com.rizzog99.personalfinancetracker.domain.travel

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * What a trip cost, from its members (#284). A port of frozen iOS `TravelReport.swift`:
 * expenses are negative, income positive; `spent` is the expenses' magnitude, `refunded` any
 * positive amount, `net` the signed sum.
 */
data class TravelReport(
    val spent: BigDecimal,
    val refunded: BigDecimal,
    val net: BigDecimal,
    val count: Int,
    val start: LocalDate?,
    val end: LocalDate?,
    /** Inclusive days spanned: 1 for a single-day trip, 0 when empty. */
    val dayCount: Int,
    /** Spending per day, to the cent; zero for an empty trip. */
    val perDay: BigDecimal,
    /** Expense categories (labels), biggest spend first, ties by name. Refunds excluded. */
    val categories: List<Pair<String, BigDecimal>>,
) {
    companion object {
        fun of(members: List<FinanceTransaction>, zone: ZoneId): TravelReport {
            var spent = BigDecimal.ZERO
            var refunded = BigDecimal.ZERO
            val byCategory = linkedMapOf<String, BigDecimal>()
            members.forEach { member ->
                if (member.amount < BigDecimal.ZERO) {
                    val magnitude = member.amount.negate()
                    spent += magnitude
                    byCategory[member.categoryLabel] = (byCategory[member.categoryLabel] ?: BigDecimal.ZERO) + magnitude
                } else {
                    refunded += member.amount
                }
            }
            val days = members.map { it.timestamp.atZone(zone).toLocalDate() }
            val start = days.minOrNull()
            val end = days.maxOrNull()
            val dayCount = if (start == null || end == null) 0 else maxOf(1, ChronoUnit.DAYS.between(start, end).toInt() + 1)
            return TravelReport(
                spent = spent,
                refunded = refunded,
                net = refunded - spent,
                count = members.size,
                start = start,
                end = end,
                dayCount = dayCount,
                perDay = if (dayCount > 0) spent.divide(BigDecimal(dayCount), 2, RoundingMode.HALF_EVEN) else BigDecimal.ZERO,
                categories = byCategory.entries
                    .sortedWith(compareByDescending<Map.Entry<String, BigDecimal>> { it.value }.thenBy { it.key })
                    .map { it.key to it.value },
            )
        }
    }
}
