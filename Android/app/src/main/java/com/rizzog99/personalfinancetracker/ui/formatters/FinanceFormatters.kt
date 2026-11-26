package com.rizzog99.personalfinancetracker.ui.formatters

import android.text.format.DateFormat
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

/** Whole units, e.g. Safe to Spend's per-day figure (`€269`), as iOS `.precision(.fractionLength(0))`. */
fun formatWholeCurrency(amount: BigDecimal, currencyCode: String): String = NumberFormat
    .getCurrencyInstance(Locale.getDefault())
    .apply {
        currency = Currency.getInstance(currencyCode)
        maximumFractionDigits = 0
        minimumFractionDigits = 0
    }
    .format(amount)

/** Day and short month in the locale's order ("26 Oct", "Oct 26", "26 ott"), as iOS `.day().month(.abbreviated)`. */
fun formatDayMonth(date: LocalDate): String {
    val locale = Locale.getDefault()
    return DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "dMMM"), locale).format(date)
}

fun formatTransactionDate(timestamp: Instant): String = DateTimeFormatter
    .ofLocalizedDate(FormatStyle.MEDIUM)
    .withLocale(Locale.getDefault())
    .withZone(ZoneId.systemDefault())
    .format(timestamp)

/** Time-of-day only, e.g. for a row already grouped under a "Today"/date section header. */
fun formatTransactionTime(timestamp: Instant): String = DateTimeFormatter
    .ofLocalizedTime(FormatStyle.SHORT)
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
