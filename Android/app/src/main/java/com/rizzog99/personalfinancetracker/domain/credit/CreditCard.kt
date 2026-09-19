package com.rizzog99.personalfinancetracker.domain.credit

import java.math.BigDecimal

/**
 * A revolving credit line. Mirrors the frozen `CreditCardModel`, which stands alone: it links to no
 * transaction, so deleting one changes nothing else.
 */
data class CreditCard(
    val id: String,
    val name: String,
    val lastFour: String,
    val balance: BigDecimal,
    val limit: BigDecimal,
    val colorToken: String = DEFAULT_COLOR_TOKEN,
    val currencyCode: String = DEFAULT_CURRENCY_CODE,
)

data class NewCreditCard(
    val name: String,
    val lastFour: String,
    val balance: BigDecimal,
    val limit: BigDecimal,
    val colorToken: String = DEFAULT_COLOR_TOKEN,
    val currencyCode: String = DEFAULT_CURRENCY_CODE,
)

const val DEFAULT_COLOR_TOKEN: String = "accentIndigo"
const val DEFAULT_CURRENCY_CODE: String = "EUR"
