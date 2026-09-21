package com.rizzog99.personalfinancetracker.domain.receipt

import java.math.BigDecimal
import java.text.Normalizer
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale

data class ReceiptScan(
    val total: BigDecimal? = null,
    val totalCandidates: List<BigDecimal> = emptyList(),
    val date: LocalDate? = null,
    val dateWasClamped: Boolean = false,
    val merchant: String? = null,
    val isRefund: Boolean = false,
)

/** Pure local-text parser. OCR and image handling deliberately live outside this class. */
object ReceiptParser {
    private val amountPattern = Regex("(?:€|EUR)?\\s*(\\d{1,3}(?:[.,]\\d{3})*[.,]\\d{2}|\\d+[.,]\\d{2})")
    private val datePattern = Regex("\\b(\\d{1,2})[/.\\-](\\d{1,2})[/.\\-](\\d{2,4})\\b")
    private val totalKeywordTiers = listOf(
        listOf("TOTALE COMPLESSIVO"),
        listOf("IMPORTO PAGATO", "GRAND TOTAL", "BALANCE DUE"),
        listOf("TOTALE", "TOTAL", "IMPORTO", "TOT."),
    )
    private val ignoredTotalWords = listOf("SUBTOTALE", "SUBTOTAL", "IVA", "TAX", "CONTANTI", "CASH", "RESTO", "CHANGE")
    private val structuralWords = listOf(
        "DOCUMENTO COMMERCIALE", "SCONTRINO", "TOTALE", "TOTAL", "IMPORTO", "P.IVA", "PARTITA IVA",
        "CODICE FISCALE", "TEL.", "VIA ", "PIAZZA ", "CAP ", "POS", "PAGAMENTO",
    )
    private val refundWords = Regex("\\b(RESO|RIMBORSO|STORNO|REFUND)\\b")

    fun parse(lines: List<String>, today: LocalDate = LocalDate.now()): ReceiptScan {
        val usefulLines = lines.map(String::trim).filter(String::isNotEmpty)
        val totalCandidates = totalCandidates(usefulLines)
        val dateResult = parseDate(usefulLines, today)
        return ReceiptScan(
            total = totalCandidates.singleOrNull(),
            totalCandidates = if (totalCandidates.size > 1) totalCandidates else emptyList(),
            date = dateResult.first,
            dateWasClamped = dateResult.second,
            merchant = merchantName(usefulLines),
            isRefund = usefulLines.any { refundWords.containsMatchIn(normalize(it)) },
        )
    }

    private fun totalCandidates(lines: List<String>): List<BigDecimal> {
        totalKeywordTiers.forEach { tier ->
            val values = lines.filter { line ->
                val normalized = normalize(line)
                tier.any(normalized::contains) && ignoredTotalWords.none(normalized::contains)
            }.mapNotNull(::lastAmount)
                .distinct()
            if (values.isNotEmpty()) return values
        }
        return emptyList()
    }

    private fun parseDate(lines: List<String>, today: LocalDate): Pair<LocalDate?, Boolean> {
        val match = lines.asSequence().mapNotNull { datePattern.find(it) }.firstOrNull() ?: return null to false
        val yearText = match.groupValues[3]
        val year = yearText.toInt().let { if (yearText.length == 2) 2_000 + it else it }
        val parsed = try {
            LocalDate.of(year, match.groupValues[2].toInt(), match.groupValues[1].toInt())
        } catch (_: DateTimeParseException) {
            null
        } catch (_: RuntimeException) {
            null
        } ?: return today to true
        return if (parsed.isAfter(today) || parsed.isBefore(today.minusYears(10))) today to true else parsed to false
    }

    private fun merchantName(lines: List<String>): String? = lines.firstOrNull { line ->
        val normalized = normalize(line)
        normalized.count(Char::isLetter) >= 3 &&
            amountPattern.find(line) == null &&
            structuralWords.none(normalized::contains) &&
            !normalized.matches(Regex(".*\\b\\d{4,5}\\b.*"))
    }?.replace(Regex("\\s+"), " ")?.take(80)

    private fun lastAmount(line: String): BigDecimal? = amountPattern.findAll(line).lastOrNull()?.groupValues?.get(1)?.let(::parseAmount)

    private fun parseAmount(value: String): BigDecimal? = runCatching {
        val compact = value.replace(" ", "")
        val decimalSeparator = maxOf(compact.lastIndexOf(','), compact.lastIndexOf('.'))
        val normalized = compact.mapIndexed { index, character ->
            when {
                index == decimalSeparator -> '.'
                character == ',' || character == '.' -> null
                else -> character
            }
        }.joinToString("")
        BigDecimal(normalized)
    }.getOrNull()

    private fun normalize(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFD)
        .replace("\\p{M}".toRegex(), "")
        .uppercase(Locale.ROOT)
}
