package com.rizzog99.personalfinancetracker.domain.category

import java.util.Locale

object CategoryNameValidator {
    private val allowedPunctuation = setOf('&', '/', '-', '\'', '.', ',', '(', ')')

    fun isValid(name: String): Boolean = name.all { character ->
        character.isLetterOrDigit() || character.isWhitespace() || character in allowedPunctuation
    }

    fun normalized(name: String): String = name.trim().lowercase(Locale.ROOT)

    fun isDuplicate(name: String, names: Sequence<String>): Boolean {
        val normalized = normalized(name)
        return names.any { normalized(it) == normalized }
    }
}
