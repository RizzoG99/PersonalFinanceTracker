package com.rizzog99.personalfinancetracker.domain.import

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

data class CsvColumnMapping(
    val date: String,
    val amount: String,
    val category: String? = null,
    val note: String? = null,
    val type: String? = null,
    val dateFormat: String = "dd/MM/yyyy",
    val signConvention: SignConvention = SignConvention.EXPENSES_NEGATIVE,
)

enum class SignConvention { EXPENSES_NEGATIVE, EXPENSES_POSITIVE }

data class ImportValidationResult(
    val transactions: List<FinanceTransaction>,
    val rejectedRows: Int,
)

object TransactionImportMapper {
    val supportedDateFormats = listOf("yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "dd-MM-yyyy")

    fun validate(file: CsvImportParser.CsvFile, mapping: CsvColumnMapping): ImportValidationResult {
        val indexes = mapOf(
            "date" to file.headers.indexOf(mapping.date),
            "amount" to file.headers.indexOf(mapping.amount),
            "category" to mapping.category?.let(file.headers::indexOf),
            "note" to mapping.note?.let(file.headers::indexOf),
            "type" to mapping.type?.let(file.headers::indexOf),
        )
        require(indexes["date"]!! >= 0 && indexes["amount"]!! >= 0)
        val dateIndex = requireNotNull(indexes["date"])
        val amountIndex = requireNotNull(indexes["amount"])
        var rejected = 0
        val transactions = file.rows.mapNotNull { row -> runCatching {
            val timestamp = parseDate(row[dateIndex], mapping.dateFormat)
            var amount = parseAmount(row[amountIndex])
            val type = indexes["type"]?.let { row.getOrNull(it).orEmpty() }.orEmpty()
            amount = when {
                type.isExpenseType() -> amount.abs().negate()
                type.isIncomeType() -> amount.abs()
                mapping.signConvention == SignConvention.EXPENSES_POSITIVE -> amount.negate()
                else -> amount
            }
            FinanceTransaction(
                id = UUID.randomUUID().toString(), timestamp = timestamp, amount = amount,
                categoryLabel = indexes["category"]?.let { row.getOrNull(it).orEmpty() }.orEmpty(),
                categoryId = null, note = indexes["note"]?.let { row.getOrNull(it).orEmpty() }.orEmpty(),
                currencyCode = "EUR", goalId = null, recurrenceRuleId = null,
            )
        }.getOrElse { rejected++; null } }
        return ImportValidationResult(transactions, rejected)
    }

    private fun parseDate(value: String, pattern: String) = runCatching {
        if (pattern.contains("HH")) LocalDateTime.parse(value.trim(), DateTimeFormatter.ofPattern(pattern)).atZone(ZoneId.systemDefault()).toInstant()
        else java.time.LocalDate.parse(value.trim(), DateTimeFormatter.ofPattern(pattern)).atStartOfDay(ZoneId.systemDefault()).toInstant()
    }.getOrElse { error("Unsupported date") }

    private fun parseAmount(raw: String): BigDecimal {
        val value = raw.trim().replace("\\s".toRegex(), "")
        val normalized = when {
            value.contains(',') && value.contains('.') && value.lastIndexOf(',') > value.lastIndexOf('.') -> value.replace(".", "").replace(',', '.')
            value.contains(',') && value.contains('.') -> value.replace(",", "")
            value.contains(',') -> value.replace(',', '.')
            else -> value
        }
        return normalized.toBigDecimal()
    }
}

private fun String.isExpenseType() = trim().lowercase() in setOf("expense", "expenses", "exp", "exp.", "uscita", "uscite")
private fun String.isIncomeType() = trim().lowercase() in setOf("income", "incomes", "inc", "inc.", "entrata", "entrate")
