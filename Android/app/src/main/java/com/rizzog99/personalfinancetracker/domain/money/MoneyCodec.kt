package com.rizzog99.personalfinancetracker.domain.money

import java.math.BigDecimal

/** Canonical storage encoding for financial amounts. Never use binary floating point. */
object MoneyCodec {
    fun encode(amount: BigDecimal): String = amount.stripTrailingZeros().toPlainString()

    fun decode(encoded: String): BigDecimal {
        require(encoded.isNotBlank()) { "A money value cannot be blank." }
        return encoded.toBigDecimal()
    }
}
