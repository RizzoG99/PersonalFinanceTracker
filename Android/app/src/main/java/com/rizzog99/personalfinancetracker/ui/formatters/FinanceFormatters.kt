package com.rizzog99.personalfinancetracker.ui.formatters

import java.math.BigDecimal
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Currency
import java.util.Locale

private const val WORD_JOINER = "\u2060"

fun formatSignedCurrency(amount: BigDecimal, currencyCode: String): String {
    val formatter = NumberFormat.getCurrencyInstance(Locale.getDefault()).apply {
        currency = Currency.getInstance(currencyCode)
    }
    val sign = if (amount >= BigDecimal.ZERO) "+" else "−"
    return sign + WORD_JOINER + formatter.format(amount.abs())
}

fun formatCurrency(amount: BigDecimal, currencyCode: String): String = NumberFormat
    .getCurrencyInstance(Locale.getDefault())
    .apply { currency = Currency.getInstance(currencyCode) }
    .format(amount)

fun formatTransactionDate(timestamp: Instant): String = DateTimeFormatter
    .ofLocalizedDate(FormatStyle.MEDIUM)
    .withLocale(Locale.getDefault())
    .withZone(ZoneId.systemDefault())
    .format(timestamp)

fun formatPeriod(start: LocalDate, endInclusive: LocalDate): String = DateTimeFormatter
    .ofLocalizedDate(FormatStyle.MEDIUM)
    .withLocale(Locale.getDefault())
    .format(start) + " – " + DateTimeFormatter
    .ofLocalizedDate(FormatStyle.MEDIUM)
    .withLocale(Locale.getDefault())
    .format(endInclusive)
