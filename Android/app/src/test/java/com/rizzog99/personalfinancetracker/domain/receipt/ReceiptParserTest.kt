package com.rizzog99.personalfinancetracker.domain.receipt

import java.math.BigDecimal
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiptParserTest {
    private val today = LocalDate.of(2026, 9, 6)
    private val referenceDay = LocalDate.of(2026, 11, 28)

    @Test
    fun ac01_excludesDecoysAndReadsTotalOnNextLine() {
        val scan = ReceiptParser.parse(
            listOf("SUB TOTALE 10,00", "IVA 2,50", "TOTALE COMPLESSIVO", "12,50", "CONTANTI 20,00", "RESTO 7,50"),
            referenceDay,
        )

        assertEquals(BigDecimal("12.50"), scan.total)
        assertTrue(scan.totalCandidates.isEmpty())
    }

    @Test
    fun ac01_officialUsAmountOutranksSubtotalTipTaxAndTender() {
        val scan = ReceiptParser.parse(
            listOf("SUB TOTAL 10.00", "TOTAL TAX 2.50", "TOTAL SAVINGS 5.99", "AMOUNT DUE 12.50", "SUGGESTED TIP 3.00", "CASH 20.00", "CHANGE 7.50"),
            referenceDay,
        )

        assertEquals(BigDecimal("12.50"), scan.total)
        assertTrue(scan.totalCandidates.isEmpty())
    }

    @Test
    fun ac01_totalTaxAndSavingsNeverBecomeTotalCandidates() {
        val scan = ReceiptParser.parse(listOf("TOTAL TAX 2.50", "TOTAL SAVINGS 5.99"), referenceDay)

        assertNull(scan.total)
        assertTrue(scan.totalCandidates.isEmpty())
    }

    @Test
    fun ac01_equalOfficialTotalsCollapseAndUnlabeledPricesDoNotProposeTotal() {
        val repeated = ReceiptParser.parse(listOf("TOTALE COMPLESSIVO 12,50", "TOTALE COMPLESSIVO 12.50"), referenceDay)
        val unlabeled = ReceiptParser.parse(listOf("2,50", "2,50", "12,50"), referenceDay)

        assertEquals(BigDecimal("12.50"), repeated.total)
        assertTrue(repeated.totalCandidates.isEmpty())
        assertNull(unlabeled.total)
        assertTrue(unlabeled.totalCandidates.isEmpty())
    }

    @Test
    fun ac01_pairsColumnsByGeometryEvenWhenPricePrecedesLabelInOcrOrder() {
        val document = ReceiptDocument(
            listOf(
                line("20,00", 525, 180),
                line("12,50", 525, 150),
                line("2,50", 525, 120),
                line("CONTANTI", 45, 180),
                line("IVA", 45, 120),
                line("TOTALE COMPLESSIVO", 45, 150),
            ),
        )

        val scan = ReceiptParser.parse(document, referenceDay)

        assertEquals(BigDecimal("12.50"), scan.total)
        assertTrue(scan.totalCandidates.isEmpty())
    }

    @Test
    fun ac01_rejectsOrphanTotalBesideAnotherRow() {
        val document = ReceiptDocument(
            listOf(
                line("TOTAL", 45, 80),
                line("2.50", 525, 112),
                line("SALES TAX", 45, 112),
            ),
        )

        val scan = ReceiptParser.parse(document, referenceDay)

        assertNull(scan.total)
        assertTrue(scan.totalCandidates.isEmpty())
    }

    @Test
    fun ac02_readsUsDateIndependentlyOfAppLocale() {
        val american = ReceiptParser.parse(listOf("ORCHARD CAFE", "11/05/2026", "TOTAL DUE 1,234.56"), referenceDay)
        val italian = ReceiptParser.parse(listOf("MERCATO AURORA", "11/05/2026", "TOTALE COMPLESSIVO 1.234,56"), referenceDay)

        assertEquals(BigDecimal("1234.56"), american.total)
        assertEquals(LocalDate.of(2026, 11, 5), american.date)
        assertFalse(american.dateWasClamped)
        assertEquals(BigDecimal("1234.56"), italian.total)
        assertEquals(LocalDate.of(2026, 5, 11), italian.date)
        assertFalse(italian.dateWasClamped)
    }

    @Test
    fun ac02_keepsTryingDatesAndClampsUnknownToReferenceDay() {
        val usable = ReceiptParser.parse(listOf("32/13/2026", "05/11/2026", "TOTALE 12,50"), referenceDay)
        val old = ReceiptParser.parse(listOf("25/11/2023", "TOTALE 12,50"), referenceDay)
        val missing = ReceiptParser.parse(listOf("TOTALE 12,50"), referenceDay)
        val future = ReceiptParser.parse(listOf("12/01/2026", "TOTAL DUE 12.50"), referenceDay)

        assertEquals(LocalDate.of(2026, 11, 5), usable.date)
        assertFalse(usable.dateWasClamped)
        assertEquals(referenceDay, old.date)
        assertTrue(old.dateWasClamped)
        assertEquals(referenceDay, missing.date)
        assertTrue(missing.dateWasClamped)
        assertEquals(referenceDay, future.date)
        assertTrue(future.dateWasClamped)
    }

    @Test
    fun ac02_recognizesLimitedOcrLabelMisspellingAndWholeWordRefunds() {
        val refund = ReceiptParser.parse(
            listOf("CREMERIA AURORA", "DOCUMENTO COMMERCIALE DI RESO", "T0TALE COMPLESSIVO 12,50"),
            referenceDay,
        )
        val purchase = ReceiptParser.parse(listOf("RESORT AURORA", "GRAND TOTAL 12.50"), referenceDay)
        val englishRefund = ReceiptParser.parse(listOf("REFUND", "TOTAL DUE 12.50"), referenceDay)

        assertTrue(refund.isRefund)
        assertEquals(BigDecimal("12.50"), refund.total)
        assertFalse(purchase.isRefund)
        assertEquals("RESORT AURORA", purchase.merchant)
        assertTrue(englishRefund.isRefund)
    }

    @Test
    fun ac02_usesMerchantProminenceBeforeItemTableIndependentOfOcrOrder() {
        val document = ReceiptDocument(
            listOf(
                line("DESCRIZIONE", 45, 120, height = 35),
                line("Via Roma", 45, 67),
                line("BENVENUTI", 45, 20, height = 12),
                line("CAFÉ AURORA", 45, 36, height = 28),
                line("PANE 4,20", 45, 166),
            ),
        )

        assertEquals("CAFÉ AURORA", ReceiptParser.parse(document, referenceDay).merchant)
    }

    private fun line(text: String, x: Int, y: Int, height: Int = 15) =
        ReceiptLine(text, ReceiptBounds(x.toFloat(), y.toFloat(), x + text.length * 7f, (y + height).toFloat()))

    @Test
    fun ac03_ordersOnlyTheConflictingCredibleTotals() {
        val scan = ReceiptParser.parse(
            listOf("TOTALE COMPLESSIVO 15,00", "IVA 2,50", "TOTALE COMPLESSIVO 12,50", "CONTANTI 20,00"),
            referenceDay,
        )

        assertNull(scan.total)
        assertEquals(listOf(BigDecimal("12.50"), BigDecimal("15.00")), scan.totalCandidates)
    }

    @Test
    fun ac03_keepsConflictingQualifiedTotalLabels() {
        val scan = ReceiptParser.parse(
            listOf("GRAND TOTAL 12.50", "TOTALE COMPLESSIVO 15,00", "IMPORTO SCONTO 2,50"),
            referenceDay,
        )

        assertNull(scan.total)
        assertEquals(listOf(BigDecimal("12.50"), BigDecimal("15.00")), scan.totalCandidates)
    }

    @Test
    fun ac01_readsSpaceGroupedPricesAndRejectsDiscountTotals() {
        val grouped = ReceiptParser.parse(listOf("TOTAL DUE 1\u00a0234.56"), referenceDay)
        val discount = ReceiptParser.parse(listOf("TOTAL DISCOUNT 5.00", "TOTALE SCONTI 5,00"), referenceDay)

        assertEquals(BigDecimal("1234.56"), grouped.total)
        assertNull(discount.total)
        assertTrue(discount.totalCandidates.isEmpty())
    }

    @Test
    fun ac03_twoAmountsOnOneTotalLineStayAmbiguous() {
        val scan = ReceiptParser.parse(listOf("TOTAL DUE 12.50 15.00"), referenceDay)

        assertNull(scan.total)
        assertEquals(listOf(BigDecimal("12.50"), BigDecimal("15.00")), scan.totalCandidates)
    }

    @Test
    fun ac03_twoPricesAlignedWithOneTotalLabelStayAmbiguous() {
        val document = ReceiptDocument(
            listOf(line("TOTAL DUE", 45, 150), line("12.50", 350, 150), line("15.00", 525, 150)),
        )

        val scan = ReceiptParser.parse(document, referenceDay)

        assertNull(scan.total)
        assertEquals(listOf(BigDecimal("12.50"), BigDecimal("15.00")), scan.totalCandidates)
    }

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
