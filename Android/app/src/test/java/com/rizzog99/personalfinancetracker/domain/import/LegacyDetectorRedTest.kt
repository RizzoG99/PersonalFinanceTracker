package com.rizzog99.personalfinancetracker.domain.import

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Temporary red-first evidence for #295: the AC-02 negative fixtures run through the import
 * detector that ships today. Deleted together with RecurringImportDetector in the fix commit.
 */
class LegacyDetectorRedTest {
    private fun row(note: String, amount: String, date: String) = FinanceTransaction(
        id = "$note-$date", timestamp = Instant.parse("${date}T12:00:00Z"), amount = BigDecimal(amount),
        note = note, categoryLabel = "Gifts", categoryId = null, currencyCode = "EUR", goalId = null, recurrenceRuleId = null,
    )

    @Test
    fun `ac02 two yearly gifts and a 3,50 coffee are not suggested`() {
        val rows = listOf(
            row("Regalo Sofia", "-10", "2025-12-09"), row("Regalo Sofia", "-10", "2026-12-09"),
            row("San Martino", "-35", "2024-11-11"), row("San Martino", "-35", "2025-11-11"),
            row("Caffè", "-3.50", "2026-10-06"), row("Caffè", "-3.50", "2026-10-13"), row("Caffè", "-3.50", "2026-10-20"),
        )
        assertEquals(emptyList<Any>(), RecurringImportDetector.detect(rows).map { it.note })
    }
}
