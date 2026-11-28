package com.rizzog99.personalfinancetracker.domain.receipt

import java.math.BigDecimal
import java.text.Normalizer
import java.time.DateTimeException
import java.time.LocalDate
import java.util.Locale
import kotlin.math.abs

data class ReceiptScan(
    val total: BigDecimal? = null,
    val totalCandidates: List<BigDecimal> = emptyList(),
    val date: LocalDate? = null,
    val dateWasClamped: Boolean = false,
    val merchant: String? = null,
    val isRefund: Boolean = false,
)

/** Pure receipt parser. The recognizer supplies positions when the image has readable layout. */
object ReceiptParser {
    private const val MONEY = """(?:\d{1,3}(?:[.,\p{Zs}]\d{3})+|\d+)[.,]\d{2}"""
    private val amountPattern = Regex("""(?<![\d.,/])($MONEY)(?![\d.,/])""")
    private val bareAmount = Regex("""(?i)(?:€|\$|EUR|USD)?\s*($MONEY)\s*(?:€|\$|EUR|USD)?""")
    private val datePattern = Regex("\\b(\\d{1,2})[/.\\-](\\d{1,2})[/.\\-](\\d{2,4})\\b")
    private val totalKeywordTiers = listOf(
        listOf("TOTALE COMPLESSIVO", "IMPORTO PAGATO", "GRAND TOTAL", "TOTAL DUE", "BALANCE DUE", "AMOUNT DUE"),
        listOf("TOTALE", "TOTAL", "IMPORTO", "TOT"),
    )
    private val ignoredTotalWords = listOf(
        "SUBTOTALE", "SUB TOTALE", "SUBTOTAL", "SUB TOTAL", "NET TOTAL", "SAVINGS", "RISPARMIO",
        "IVA", "VAT", "TAX", "CONTANTE", "CONTANTI", "CASH", "TENDER", "RESTO", "CHANGE",
        "TIP", "GRATUITY", "MANCIA", "DISCOUNT", "DISCOUNTS", "SCONTO", "SCONTI",
    )
    private val structuralWords = listOf(
        "DOCUMENTO COMMERCIALE", "SCONTRINO", "RECEIPT", "TOTALE", "TOTAL", "IMPORTO", "P IVA", "PARTITA IVA",
        "CODICE FISCALE", "TEL", "VIA", "PIAZZA", "CAP", "POS", "PAGAMENTO", "THANK YOU", "MERCHANT COPY",
        "DATE", "DATA", "CASHIER", "SERVER", "BENVENUTI", "WELCOME", "REFUND",
    )
    private val italianMarkers = listOf("TOTALE", "IMPORTO", "SCONTRINO", "DOCUMENTO", "PREZZO", "IVA")
    private val englishMarkers = listOf("TOTAL", "SUBTOTAL", "SUB TOTAL", "THANK YOU", "SERVER", "CASHIER", "AMOUNT DUE")
    private val ocrTotalSpellings = mapOf("T0TALE" to "TOTALE", "T0TAL" to "TOTAL", "C0MPLESSIVO" to "COMPLESSIVO")
    private val nonWord = Regex("""[^\p{L}\p{N}]+""")
    private val marks = Regex("""\p{M}+""")
    private val postalCode = Regex("""\b\d{4,5}\b""")
    private val itemTableHeaders = listOf("DESCRIZIONE", "DESCRIPTION", "DESCRIPTLON", "QTY", "QUANTITA")
    private val refundWords = Regex("\\b(RESO|RIMBORSO|STORNO|REFUND)\\b")

    fun parse(lines: List<String>, today: LocalDate = LocalDate.now()): ReceiptScan =
        parse(ReceiptDocument(lines.map { ReceiptLine(it) }), today)

    fun parse(document: ReceiptDocument, today: LocalDate = LocalDate.now()): ReceiptScan {
        val lines = document.lines.mapNotNull { line ->
            line.text.trim().takeIf(String::isNotEmpty)?.let { line.copy(text = it) }
        }
        val normalized = lines.map { normalize(it.text) }
        val totalCandidates = totalCandidates(lines, normalized)
        val date = parseDate(lines, today, prefersMonthFirst(normalized))
        return ReceiptScan(
            total = totalCandidates.singleOrNull(),
            totalCandidates = if (totalCandidates.size > 1) totalCandidates else emptyList(),
            date = date ?: today,
            dateWasClamped = date == null,
            merchant = merchantName(lines, normalized),
            isRefund = normalized.any(refundWords::containsMatchIn),
        )
    }

    private fun totalCandidates(lines: List<ReceiptLine>, normalized: List<String>): List<BigDecimal> {
        val hasLayout = lines.any { it.bounds != null }
        val rowAmounts = if (hasLayout) pairColumnAmounts(lines, normalized) else emptyMap()
        for (tier in totalKeywordTiers) {
            val matches = normalized.indices.flatMap { index ->
                val line = normalized[index]
                if (!line.hasAnyPhrase(tier) || line.hasAnyPhrase(ignoredTotalWords)) return@flatMap emptyList()
                val candidates = amountsOnLine(lines[index].text) + rowAmounts[index].orEmpty()
                if (candidates.isNotEmpty() || hasLayout) {
                    candidates
                } else {
                    listOfNotNull(lines.getOrNull(index + 1)?.text?.let(::onlyAmount))
                }
            }.toSortedSet()
            if (matches.isNotEmpty()) return matches.toList()
        }
        return emptyList()
    }

    private fun pairColumnAmounts(lines: List<ReceiptLine>, normalized: List<String>): Map<Int, List<BigDecimal>> {
        val labelIndices = normalized.indices.filter { index ->
            lines[index].bounds != null && normalized[index].any(Char::isLetter) && onlyAmount(lines[index].text) == null
        }
        val totalLabels = totalKeywordTiers.flatten()
        val amountsByLabel = mutableMapOf<Int, MutableList<BigDecimal>>()
        for (line in lines) {
            val price = onlyAmount(line.text) ?: continue
            val priceBounds = line.bounds ?: continue
            // Any label, including a tax or item label, can own the amount. Never hand it to the
            // nearest *total* just because the actual row's label would be rejected as a decoy.
            val owners = labelIndices.mapNotNull { index ->
                val label = requireNotNull(lines[index].bounds)
                val difference = abs(label.centerY - priceBounds.centerY)
                if (label.right <= priceBounds.left && difference <= minOf(label.height, priceBounds.height) * 0.6f) {
                    index to difference
                } else {
                    null
                }
            }.sortedBy { it.second }
            val (index, distance) = owners.firstOrNull() ?: continue
            if (owners.getOrNull(1)?.second == distance || !normalized[index].hasAnyPhrase(totalLabels)) continue
            amountsByLabel.getOrPut(index, ::mutableListOf).add(price)
        }
        return amountsByLabel
    }

    private fun prefersMonthFirst(lines: List<String>): Boolean =
        lines.none { it.hasAnyPhrase(italianMarkers) } && lines.any { it.hasAnyPhrase(englishMarkers) }

    private fun parseDate(lines: List<ReceiptLine>, today: LocalDate, monthFirst: Boolean): LocalDate? {
        val earliest = today.minusYears(2)

        fun date(year: Int, month: Int, day: Int): LocalDate? = try {
            LocalDate.of(year, month, day)
        } catch (_: DateTimeException) {
            null
        }

        for (line in lines) {
            for (match in datePattern.findAll(line.text)) {
                val (_, first, second, yearText) = match.groupValues
                if (yearText.length != 2 && yearText.length != 4) continue
                val year = yearText.toInt() + if (yearText.length == 2) 2_000 else 0
                val month = (if (monthFirst) first else second).toInt()
                val day = (if (monthFirst) second else first).toInt()
                val parsed = date(year, month, day) ?: date(year, day, month)
                if (parsed != null && parsed in earliest..today) return parsed
            }
        }
        return null
    }

    private fun merchantName(lines: List<ReceiptLine>, normalized: List<String>): String? {
        val headerIndices = normalized.indices.filter { isItemTableHeader(normalized[it]) }
        val headerTop = headerIndices.mapNotNull { lines[it].bounds?.top }.minOrNull()
        val headerIndex = headerIndices.firstOrNull()?.takeIf { it > 0 } ?: lines.size
        val candidates = normalized.indices.filter { index ->
            val line = lines[index]
            val text = normalized[index]
            val position = line.bounds
            val beforeItems = if (headerTop != null && position != null) {
                position.centerY < headerTop
            } else {
                index < minOf(headerIndex, 15)
            }
            beforeItems && index !in headerIndices && text.count(Char::isLetter) >= 3 &&
                !text.hasAnyPhrase(structuralWords) && !text.hasAnyPhrase(ignoredTotalWords) &&
                !amountPattern.containsMatchIn(line.text) && !postalCode.containsMatchIn(text)
        }
        val merchant = candidates.maxByOrNull { lines[it].bounds?.height ?: 0f } ?: return null
        return lines[merchant].text.replace(Regex("\\s+"), " ").take(80)
    }

    private fun isItemTableHeader(text: String): Boolean =
        text.hasAnyPhrase(itemTableHeaders) ||
            text == "ITEM" || text == "ITEMS"

    private fun amountsOnLine(line: String): List<BigDecimal> =
        amountPattern.findAll(line).mapNotNull { parseAmount(it.groupValues[1]) }.toList()

    private fun onlyAmount(line: String): BigDecimal? = bareAmount.matchEntire(line)?.groupValues?.get(1)?.let(::parseAmount)

    private fun parseAmount(value: String): BigDecimal? {
        val decimalSeparator = maxOf(value.lastIndexOf(','), value.lastIndexOf('.'))
        val whole = value.substring(0, decimalSeparator).filter(Char::isDigit)
        val fraction = value.substring(decimalSeparator + 1)
        return "$whole.$fraction".toBigDecimalOrNull()
    }

    private fun normalize(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFKD)
        .replace(marks, "")
        .uppercase(Locale.ROOT)
        .replace(nonWord, " ")
        .trim()
        .split(' ')
        .joinToString(" ") { ocrTotalSpellings[it] ?: it }

    private fun String.hasAnyPhrase(phrases: List<String>): Boolean {
        val padded = " $this "
        return phrases.any { phrase -> " $phrase " in padded }
    }
}
