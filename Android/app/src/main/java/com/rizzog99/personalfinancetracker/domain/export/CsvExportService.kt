package com.rizzog99.personalfinancetracker.domain.export

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Android's CSV export uses the same columns and signed-amount rule as iOS. */
object CsvExportService {
    private val dateFormatter = DateTimeFormatter
        .ofPattern("yyyy-MM-dd HH:mm:ss", Locale.ROOT)
        .withZone(ZoneId.systemDefault())

    fun generate(transactions: List<FinanceTransaction>): String = buildString {
        append("Date,Amount,Currency,Category,Note,Type\n")
        transactions.sortedByDescending(FinanceTransaction::timestamp).forEachIndexed { index, transaction ->
            if (index > 0) append('\n')
            append(dateFormatter.format(transaction.timestamp))
            append(',')
            append(transaction.amount.toPlainString())
            append(',')
            append(escape(transaction.currencyCode))
            append(',')
            append(escape(transaction.categoryLabel))
            append(',')
            append(escape(transaction.note))
            append(',')
            append(if (transaction.amount.signum() >= 0) "Income" else "Expense")
        }
    }

    private fun escape(value: String): String = if (value.any { it == ',' || it == '"' || it == '\n' || it == '\r' }) {
        "\"${value.replace("\"", "\"\"")}\""
    } else {
        value
    }
}
