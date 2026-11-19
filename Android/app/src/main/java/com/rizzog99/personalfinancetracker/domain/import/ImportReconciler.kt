package com.rizzog99.personalfinancetracker.domain.import

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.RoundingMode
import java.time.Duration

/**
 * Which imported rows are already in the ledger (#314). iOS `confirmImport` step 6 at b649dff
 * (`TransactionListViewModel.swift`): a row is a duplicate when its (timestamp, amount, note)
 * already exists, or when it is the bank's copy of a payment an auto-record rule wrote, matched on
 * the amount to the cent within 3 days, each generated row absorbing at most one imported row.
 * Used by the preview and again at commit, against a fresh read, so both agree.
 */
object ImportReconciler {
    private val window: Duration = Duration.ofDays(3)

    /** (rows to save, rows already in [existing]). */
    fun split(incoming: List<FinanceTransaction>, existing: List<FinanceTransaction>): Pair<List<FinanceTransaction>, List<FinanceTransaction>> {
        val keys = existing.mapTo(HashSet()) { Triple(it.timestamp, it.amount.stripTrailingZeros(), it.note) }
        // Forecast-only rules (#295) never insert rows, so every row with a rule is auto-recorded.
        val generated = existing.filter { it.recurrenceRuleId != null }.toMutableList()
        val fresh = mutableListOf<FinanceTransaction>()
        val duplicates = mutableListOf<FinanceTransaction>()
        for (row in incoming) {
            if (Triple(row.timestamp, row.amount.stripTrailingZeros(), row.note) in keys) {
                duplicates += row
                continue
            }
            // ponytail: keeps the generated row and drops the bank's, like iOS; replace it instead if the real booking date matters.
            val match = generated.indexOfFirst {
                it.amount.cents() == row.amount.cents() && Duration.between(it.timestamp, row.timestamp).abs() <= window
            }
            if (match >= 0) {
                generated.removeAt(match)
                duplicates += row
            } else {
                fresh += row
            }
        }
        return fresh to duplicates
    }

    private fun java.math.BigDecimal.cents() = setScale(2, RoundingMode.HALF_UP)
}
