package com.rizzog99.personalfinancetracker.domain.money

import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Test

class MoneyCodecTest {
    @Test
    fun `encodes signed decimal values without floating point loss`() {
        assertEquals("-19.99", MoneyCodec.encode(BigDecimal("-19.990")))
        assertEquals("1234567890.123456789", MoneyCodec.encode(BigDecimal("1234567890.123456789")))
    }

    @Test
    fun `decodes canonical decimal values exactly`() {
        assertEquals(BigDecimal("0.10"), MoneyCodec.decode("0.10"))
    }
}
