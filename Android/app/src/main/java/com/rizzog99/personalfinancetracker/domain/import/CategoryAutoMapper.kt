package com.rizzog99.personalfinancetracker.domain.import

import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory

/**
 * Matches CSV category names against the app's own categories, across languages.
 * Ported from iOS's `CategoryAutoMapper.swift` so the two imports recognize the same names.
 */
object CategoryAutoMapper {
    /** Canonical keyword -> synonyms in multiple languages. */
    private val synonyms: Map<String, List<String>> = mapOf(
        "grocer" to listOf("spesa", "supermercato", "alimentari", "lebensmittel", "épicerie", "comestibles"),
        "restaurant" to listOf(
            "ristorante", "colazione", "pranzo", "cena", "bar", "caffè", "trattoria",
            "restaurant", "gaststätte", "comida",
        ),
        "transport" to listOf(
            "trasporti", "trasporto", "moto", "auto", "veicolo", "benzina", "carburante",
            "treno", "bus", "metro", "transporte", "verkehr",
        ),
        "travel" to listOf("viaggi", "viaggio", "vacanza", "esperienze", "hotel", "volo", "reise", "voyage"),
        "shopping" to listOf("acquisti", "acquisto", "vestiti", "abbigliamento", "einkauf", "achat"),
        "subscript" to listOf("abbonamenti", "abbonamento", "abonnement", "abonnierung"),
        "entertain" to listOf("intrattenimento", "divertimento", "cinema", "teatro", "unterhaltung", "loisir"),
        "health" to listOf("salute", "benessere", "medico", "farmacia", "dottore", "gesundheit", "santé"),
        "fitness" to listOf("palestra", "sport", "allenamento", "fitness", "fitnessstudio"),
        "beauty" to listOf("parrucchiere", "estetista", "bellezza", "cura", "schönheit"),
        "gift" to listOf("regali", "regalo", "dono", "geschenk", "cadeau"),
        "salary" to listOf("stipendio", "salario", "retribuzione", "gehalt", "salaire"),
        "invest" to listOf("investimenti", "investimento", "borsa", "azioni", "investition"),
        "house" to listOf("casa", "affitto", "mutuo", "haus", "miete", "maison", "loyer"),
        "util" to listOf("bollette", "bolletta", "luce", "gas", "acqua", "internet", "strom", "nebenkosten"),
        "edu" to listOf("istruzione", "scuola", "università", "libri", "bildung", "école"),
        "pet" to listOf("animali", "animale", "veterinario", "haustier", "vétérinaire"),
        "other" to listOf("altro", "varie", "vario", "sonstiges", "autre", "otros"),
    )

    /** Synonym -> its canonical keyword (flattened, lowercased, pre-built once). */
    private val synonymLookup: Map<String, String> = buildMap {
        synonyms.forEach { (canonical, words) -> words.forEach { word -> put(word, canonical) } }
    }

    /** Returns the canonical keyword set for a given string (CSV category or app category name). */
    private fun canonicalKeywords(text: String): Set<String> {
        val tokens = text.lowercase().split(Regex("[^\\p{L}\\p{Nd}]+")).filter { it.length > 2 }
        val keys = mutableSetOf<String>()
        for (token in tokens) {
            val canonical = synonymLookup[token]
                ?: synonyms.keys.firstOrNull { token.startsWith(it) || it.startsWith(token) }
            if (canonical != null) keys.add(canonical)
            keys.add(token)
        }
        return keys
    }

    /**
     * 1. Exact name match.
     * 2. Most-keyword-overlap match (multilingual synonyms, English inflections via prefix match).
     * 3. Substring fallback.
     */
    fun bestMatch(csv: String, pool: List<FinanceCategory>): FinanceCategory? {
        pool.firstOrNull { it.name.equals(csv, ignoreCase = true) }?.let { return it }

        val csvKeys = canonicalKeywords(csv)
        var bestScore = 0
        var best: FinanceCategory? = null
        for (category in pool) {
            val overlap = csvKeys.intersect(canonicalKeywords(category.name)).size
            if (overlap > bestScore) {
                bestScore = overlap
                best = category
            }
        }
        if (bestScore > 0) return best

        val lower = csv.lowercase()
        return pool.firstOrNull { lower.contains(it.name.lowercase()) || it.name.lowercase().contains(lower) }
    }
}
