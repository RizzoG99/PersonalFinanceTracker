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
    val signConvention: SignConvention = SignConvention.SIGNED,
)

/** Mirrors iOS's ColumnMapping.signConvention; only used when [CsvColumnMapping.type] is unmapped. */
enum class SignConvention { SIGNED, ALL_EXPENSES, ALL_INCOME }

data class ImportValidationResult(
    val transactions: List<FinanceTransaction>,
    val rejectedRows: Int,
    /**
     * Account moves, dropped on purpose rather than counted as income or expense. Reported
     * separately because they are not errors, but they do explain why fewer transactions come out
     * than the file has rows — which previously looked like rows silently going missing.
     */
    val skippedTransfers: Int = 0,
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
        var skippedTransfers = 0
        val transactions = file.rows.mapNotNull { row ->
            val type = indexes["type"]?.let { row.getOrNull(it).orEmpty() }.orEmpty()
            // Transfer rows represent account moves, not income/expense — skip like iOS does.
            if (type.isTransferType()) { skippedTransfers++; return@mapNotNull null }
            runCatching {
                val timestamp = parseDate(row[dateIndex], mapping.dateFormat)
                var amount = parseAmount(row[amountIndex])
                amount = when {
                    type.isExpenseType() -> amount.abs().negate()
                    type.isIncomeType() -> amount.abs()
                    mapping.signConvention == SignConvention.ALL_EXPENSES -> amount.abs().negate()
                    mapping.signConvention == SignConvention.ALL_INCOME -> amount.abs()
                    else -> amount
                }
                FinanceTransaction(
                    id = UUID.randomUUID().toString(), timestamp = timestamp, amount = amount,
                    categoryLabel = indexes["category"]?.let { row.getOrNull(it).orEmpty() }.orEmpty(),
                    categoryId = null, note = indexes["note"]?.let { row.getOrNull(it).orEmpty() }.orEmpty(),
                    currencyCode = "EUR", goalId = null, recurrenceRuleId = null,
                )
            }.getOrElse { rejected++; null }
        }
        return ImportValidationResult(transactions, rejected, skippedTransfers)
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
private fun String.isTransferType(): Boolean {
    val lower = trim().lowercase()
    return lower.contains("transfer") || lower.contains("trasferim") || lower == "giro" || lower.contains("giroconto")
}

private val emojiCodePointRanges = listOf(
    0x1F300..0x1F9FF, 0x2600..0x27BF, 0x1F600..0x1F64F, 0x1F900..0x1F9FF, 0x1FA00..0x1FA6F, 0x1FA70..0x1FAFF,
    0xFE00..0xFE0F, // variation selectors (e.g. the "️" after 🏍)
)

/** Mirrors iOS's `String.removingLeadingEmoji`: strips a leading emoji/pictograph and the
 * whitespace after it, so a CSV category like "🛒 Spesa" matches an app category named "Spesa". */
fun String.removingLeadingEmoji(): String {
    var index = 0
    while (index < length) {
        val codePoint = codePointAt(index)
        val isEmoji = emojiCodePointRanges.any { it.contains(codePoint) } || Character.getType(codePoint) == Character.OTHER_SYMBOL.toInt()
        if (isEmoji) {
            index += Character.charCount(codePoint)
        } else if (this[index].isWhitespace()) {
            index += 1
        } else {
            break
        }
    }
    return if (index >= length) this else substring(index)
}
