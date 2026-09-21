package com.rizzog99.personalfinancetracker.domain.pulse

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.time.Instant
import java.time.ZoneId

data class FinancialPulseMetrics(
    val todayTransactionCount: Int,
    val streakDays: Int,
)

/**
 * Computes Financial Pulse metrics from a list of transactions.
 *
 * Streak definition: Walk backward day by day from today; a day "counts" if any
 * transaction has a timestamp on that local calendar day. The streak is the number
 * of consecutive counting days starting from today (or yesterday if today has no
 * transactions yet). If today has no transactions yet, the streak includes yesterda
 * and goes backward as long as consecutive days have transactions.
 */
object FinancialPulseCalculator {
    fun calculate(
        transactions: List<FinanceTransaction>,
        now: Instant,
        zoneId: ZoneId,
    ): FinancialPulseMetrics {
        val today = now.atZone(zoneId).toLocalDate()

        // Count transactions for today
        val todayStart = today.atStartOfDay(zoneId).toInstant()
        val todayEnd = today.atStartOfDay(zoneId).plusDays(1).toInstant()
        val todayCount = transactions.count { tx ->
            tx.timestamp >= todayStart && tx.timestamp < todayEnd
        }

        // Build a set of dates with transactions for efficient lookup
        val datesWithTransactions = transactions.asSequence()
            .map { tx ->
                tx.timestamp.atZone(zoneId).toLocalDate()
            }
            .toSet()

        // Calculate streak: start from today and walk backward
        var streakLength = 0
        var currentDate = today

        // If today has transactions, include it
        if (datesWithTransactions.contains(currentDate)) {
            streakLength = 1
            currentDate = currentDate.minusDays(1)

            // Continue backward while we have consecutive days
            while (datesWithTransactions.contains(currentDate)) {
                streakLength++
                currentDate = currentDate.minusDays(1)
            }
        } else {
            // If today has no transactions, start from yesterday
            currentDate = today.minusDays(1)
            while (datesWithTransactions.contains(currentDate)) {
                streakLength++
                currentDate = currentDate.minusDays(1)
            }
        }

        return FinancialPulseMetrics(
            todayTransactionCount = todayCount,
            streakDays = streakLength,
        )
    }
}
