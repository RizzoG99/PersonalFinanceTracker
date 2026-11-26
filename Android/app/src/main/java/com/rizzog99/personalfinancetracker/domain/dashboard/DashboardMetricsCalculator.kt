package com.rizzog99.personalfinancetracker.domain.dashboard

import com.rizzog99.personalfinancetracker.domain.paycycle.FinancialPeriod
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.ZoneId

/** Home's cycle tiles and recent rows. The all-time balance hero became Safe to Spend (#298). */
data class DashboardMetrics(
    val periodIncome: BigDecimal,
    val periodExpenses: BigDecimal,
    val recentTransactions: List<FinanceTransaction>,
)

object DashboardMetricsCalculator {
    fun calculate(
        transactions: List<FinanceTransaction>,
        period: FinancialPeriod,
        zoneId: ZoneId,
        recentLimit: Int = 5,
    ): DashboardMetrics {
        require(recentLimit >= 0) { "Recent transaction limit cannot be negative." }
        var periodIncome = BigDecimal.ZERO
        var periodExpenses = BigDecimal.ZERO

        transactions.forEach { transaction ->
            if (transaction.timestamp.atZone(zoneId).toLocalDate() in period) {
                when {
                    transaction.amount > BigDecimal.ZERO -> periodIncome += transaction.amount
                    transaction.amount < BigDecimal.ZERO -> periodExpenses += transaction.amount.abs()
                }
            }
        }

        return DashboardMetrics(
            periodIncome = periodIncome,
            periodExpenses = periodExpenses,
            recentTransactions = transactions
                .sortedByDescending(FinanceTransaction::timestamp)
                .take(recentLimit),
        )
    }
}
