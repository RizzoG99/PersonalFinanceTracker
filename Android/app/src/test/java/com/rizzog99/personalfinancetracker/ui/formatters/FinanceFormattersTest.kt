package com.rizzog99.personalfinancetracker.ui.formatters

import java.math.BigDecimal
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class FinanceFormattersTest {
    @Test
    fun `keeps the sign attached to positive and negative currency values`() {
        val originalLocale = Locale.getDefault()
        Locale.setDefault(Locale.US)

        try {
            assertEquals("+\u2060€2,500.00", formatSignedCurrency(BigDecimal("2500"), "EUR"))
            assertEquals("−\u2060€2,500.00", formatSignedCurrency(BigDecimal("-2500"), "EUR"))
        } finally {
            Locale.setDefault(originalLocale)
        }
    }
}
