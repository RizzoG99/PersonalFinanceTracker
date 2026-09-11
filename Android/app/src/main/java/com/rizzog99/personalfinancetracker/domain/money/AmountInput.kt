package com.rizzog99.personalfinancetracker.domain.money

import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Locale

/** Keeps editable monetary input valid even when a hardware keyboard or paste bypasses the decimal keypad. */
object AmountInput {
    fun sanitize(input: String): String {
        var hasDecimalSeparator = false

        return buildString {
            input.forEach { character ->
                when {
                    character.isDigit() -> append(character)
                    (character == '.' || character == ',') && !hasDecimalSeparator -> {
                        append(character)
                        hasDecimalSeparator = true
                    }
                }
            }
        }
    }

    fun parse(input: String): BigDecimal? = sanitize(input)
        .trimEnd('.', ',')
        .replace(',', '.')
        .toBigDecimalOrNull()

    /** Mirrors iOS: group digits and always show two fractional digits once editing has ended. */
    fun formattedDisplay(value: BigDecimal, locale: Locale = Locale.getDefault()): String {
        val formatter = NumberFormat.getNumberInstance(locale).apply {
            minimumFractionDigits = 2
            maximumFractionDigits = 2
        }
        return "${formatter.format(value)} €"
    }
}
