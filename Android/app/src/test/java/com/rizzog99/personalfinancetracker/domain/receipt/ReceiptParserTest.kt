package com.rizzog99.personalfinancetracker.domain.receipt

import java.math.BigDecimal
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class ReceiptParserTest {
    private val today = LocalDate.of(2026, 9, 6)

    @Test
    fun `extracts the authoritative Italian total, date and merchant`() {
        val scan = ReceiptParser.parse(
            listOf(
                "SUPERMERCATO VERDE",
                "Via Roma 12",
                "Documento commerciale",
                "Data 05/09/2026",
                "TOTALE COMPLESSIVO € 23,45",
                "CONTANTI 50,00",
                "RESTO 26,55",
            ),
            today,
        )

        assertEquals(BigDecimal("23.45"), scan.total)
        assertEquals(LocalDate.of(2026, 9, 5), scan.date)
        assertEquals("SUPERMERCATO VERDE", scan.merchant)
        assertFalse(scan.isRefund)
    }

    @Test
    fun `returns candidate totals instead of guessing between conflicting matching lines`() {
        val scan = ReceiptParser.parse(
            listOf("BAR CENTRALE", "TOTALE 12,00", "IMPORTO 15,00"),
            today,
        )

        assertNull(scan.total)
        assertEquals(listOf(BigDecimal("12.00"), BigDecimal("15.00")), scan.totalCandidates)
    }

    @Test
    fun `clamps implausible future dates and detects refunds`() {
        val scan = ReceiptParser.parse(
            listOf("NEGOZIO CASA", "Data 09/09/2027", "RIMBORSO", "IMPORTO PAGATO 9.99"),
            today,
        )

        assertEquals(today, scan.date)
        assertEquals(true, scan.dateWasClamped)
        assertEquals(true, scan.isRefund)
        assertEquals(BigDecimal("9.99"), scan.total)
    }
}
