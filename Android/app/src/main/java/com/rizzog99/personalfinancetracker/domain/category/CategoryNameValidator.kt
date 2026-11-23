package com.rizzog99.personalfinancetracker.domain.category

import java.util.Locale

object CategoryNameValidator {
    private val allowedPunctuation = setOf('&', '/', '-', '\'', '.', ',', '(', ')')

    fun isValid(name: String): Boolean = name.all { character ->
        character.isLetterOrDigit() || character.isWhitespace() || character in allowedPunctuation
    }

    fun normalized(name: String): String = name.trim().lowercase(Locale.ROOT)

    /**
     * The name to store after an edit, or null when the user left it as shown. Compared with what
     * the field showed (a built-in's translation), not the stored key: saving an untouched "Spesa"
     * must keep "Groceries", or it would stop following the app language (#291, iOS #239).
     */
    fun renamedName(stored: String, edited: String, shown: String): String? {
        val trimmed = edited.trim()
        return if (trimmed == shown.trim()) null else trimmed.takeIf { it != stored }
    }

    fun isDuplicate(name: String, names: Sequence<String>): Boolean {
        val normalized = normalized(name)
        return names.any { normalized(it) == normalized }
    }
}
