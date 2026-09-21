package com.rizzog99.personalfinancetracker.domain.money

import java.math.BigDecimal
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class AmountInputTest {
    @Test
    fun `keeps digits and one decimal separator`() {
        assertEquals("123,45", AmountInput.sanitize("€ 123,45"))
        assertEquals("123.45", AmountInput.sanitize("123.45"))
    }

    @Test
    fun `rejects letters and repeated decimal separators`() {
        assertEquals("12,34", AmountInput.sanitize("a12,3x4"))
        assertEquals("12,3456", AmountInput.sanitize("12,34.56"))
    }

    @Test
    fun `parses editing text and formats its display value with grouping and cents`() {
        assertEquals(BigDecimal("100232"), AmountInput.parse("100232,"))
        assertEquals("100.232,00 €", AmountInput.formattedDisplay(BigDecimal("100232"), Locale.ITALY))
        assertEquals("100,232.00 €", AmountInput.formattedDisplay(BigDecimal("100232"), Locale.US))
    }
}
