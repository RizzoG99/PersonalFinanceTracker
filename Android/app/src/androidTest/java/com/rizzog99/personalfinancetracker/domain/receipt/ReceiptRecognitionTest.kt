package com.rizzog99.personalfinancetracker.domain.receipt

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.math.BigDecimal
import java.time.LocalDate
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReceiptRecognitionTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val referenceDay = LocalDate.of(2026, 11, 28)
    private val expectedTotal = BigDecimal("12.50")

    @Test
    fun ac01_recognizesSplitColumnsAndRetainsLayout() = runBlocking {
        val document = recognize(SyntheticReceiptImage.Kind.Clear)
        val scan = ReceiptParser.parse(document, referenceDay)

        assertTrue(document.lines.any { it.bounds != null && it.confidence != null })
        assertEquals(expectedTotal, scan.total)
        assertTrue(scan.totalCandidates.isEmpty())
        assertEquals(LocalDate.of(2026, 11, 5), scan.date)
        assertEquals("MERCATO AURORA", scan.merchant)
    }

    @Test
    fun ac02_degradedImagesReadCorrectlyOrRemainForManualReview() = runBlocking {
        val variants = listOf(
            SyntheticReceiptImage.Kind.Rotated, SyntheticReceiptImage.Kind.Angled, SyntheticReceiptImage.Kind.Dim,
        )
        variants.forEach { kind ->
            val document = recognize(kind)
            val scan = ReceiptParser.parse(document, referenceDay)
            assertTrue("$kind returned ${scan.total}", scan.total in listOf(null, expectedTotal))
            assertFalse("$kind promoted a decoy", scan.totalCandidates.any { it != expectedTotal })
            // Printed in instrumentation output for the evidence ledger, with invented data only.
            println("Receipt synthetic $kind: ${if (scan.total != null) "correct total" else "manual entry"}")
        }
    }

    @Test
    fun ac03_realRecognizerFindsBothSyntheticTotalChoices() = runBlocking {
        val scan = ReceiptParser.parse(recognize(SyntheticReceiptImage.Kind.Ambiguous), referenceDay)

        assertEquals(null, scan.total)
        assertEquals(listOf(BigDecimal("12.50"), BigDecimal("15.00")), scan.totalCandidates)
    }

    @Test
    fun ac04_unreadableImageDoesNotGenerateReceiptFields() = runBlocking {
        val document = recognize(SyntheticReceiptImage.Kind.Unreadable)
        val scan = ReceiptParser.parse(document, referenceDay)

        assertTrue(document.lines.isEmpty())
        assertEquals(null, scan.total)
        assertEquals(null, scan.merchant)
        assertTrue(scan.totalCandidates.isEmpty())
        assertTrue(scan.dateWasClamped)
    }

    private suspend fun recognize(kind: SyntheticReceiptImage.Kind): ReceiptDocument {
        val file = SyntheticReceiptImage.create(context, kind)
        return try {
            ReceiptTextRecognizer.recognize(context, Uri.fromFile(file))
        } finally {
            file.delete()
        }
    }
}
