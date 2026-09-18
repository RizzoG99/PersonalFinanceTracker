package com.rizzog99.personalfinancetracker.domain.import

import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory

/**
 * Matches CSV category names against the app's own categories, across languages.
 * Ported from iOS's `CategoryAutoMapper.swift` so the two imports recognize the same names.
 *
 * Android's default categories are identical to iOS's (see `DefaultCategories`), so the table
 * below is kept byte-for-byte in step with the Swift one. If you change one, change both.
 */
object CategoryAutoMapper {
    /**
     * Canonical keyword -> synonyms in multiple languages.
     *
     * Two rules keep this table honest, both learned the hard way on iOS:
     *
     * 1. **Every word belongs to exactly one key.** [synonymLookup] flattens this last-write-wins,
     *    so a word listed twice silently resolves to whichever key was written last.
     *    `CategoryAutoMapperTest` asserts there are no duplicates.
     * 2. **Each key lists its own name plus the words of the app category it should reach.** The
     *    table used to be one-sided — foreign word to stem — while the app's category names were
     *    only ever tokenized raw. So "affitto" resolved to the stem `house` and then matched
     *    nothing, because the category is called "Rent/Mortgage". Matching worked only where the
     *    English label happened to contain the stem ("Groceries" contains "grocer"). The reverse
     *    entries ("rent", "mortgage" under `house`) are what close that loop.
     *
     * Corollary to rule 2: a word that is itself a distinct category label must *not* be listed
     * under a broader concept, or the narrow label steals the broad concept's matches — "internet"
     * under `util` made "Bollette" resolve to the Internet category instead of Utilities, and
     * "pharmacy" under `health` sent "Doctor" to Pharmacy. Both reach their own category by exact
     * name anyway.
     *
     * Accents are handled as data, not logic: both spellings are listed, which is cheaper and more
     * predictable than folding diacritics in the tokenizer.
     */
    internal val synonyms: Map<String, List<String>> = mapOf(
        "grocer" to listOf(
            "grocer", "groceries", "supermarket", "spesa", "supermercato", "alimentari",
            "lebensmittel", "epicerie", "épicerie", "comestibles",
        ),
        "restaurant" to listOf(
            "restaurant", "restaurants", "ristorante", "ristoranti", "dining", "eating",
            "pizzeria", "colazione", "pranzo", "cena", "bar", "trattoria",
            "gaststatte", "gaststätte", "comida",
        ),
        // Split out of `restaurant` so "Caffè" reaches "Coffee & Drinks". "bar" deliberately stays
        // with the restaurants, matching iOS, where the receipt scanner maps gelaterie and
        // pasticcerie to it.
        "coffee" to listOf("coffee", "cafe", "caffe", "caffè", "kaffee"),
        "transport" to listOf(
            "transport", "public", "commute", "trasporti", "trasporto", "transporte",
            "verkehr", "treno", "train", "bus", "metro", "parking", "parcheggio",
            "auto", "veicolo", "moto",
        ),
        // Split out of `transport` so fuel reaches "Gas" rather than "Public Transport". This also
        // takes "gas" away from `util`, which is why an Italian gas *bill* now reads as fuel —
        // ambiguous either way, and no worse than before, when it landed on "Gas" regardless.
        "gas" to listOf(
            "gas", "benzina", "carburante", "petrol", "fuel", "diesel", "gasolio",
            "essence", "kraftstoff",
        ),
        "travel" to listOf(
            "travel", "viaggi", "viaggio", "vacanza", "vacation", "holiday",
            "esperienze", "hotel", "volo", "flight", "reise", "voyage",
        ),
        "shopping" to listOf("shopping", "acquisti", "acquisto", "einkauf", "achat"),
        // Split out of `shopping`: the app has both a "Shopping" and a "Clothing" category.
        "cloth" to listOf(
            "cloth", "clothing", "clothes", "vestiti", "abbigliamento", "kleidung",
            "vetements", "vêtements", "ropa",
        ),
        "subscript" to listOf(
            "subscription", "subscriptions", "streaming", "abbonamenti", "abbonamento",
            "abonnement", "abonnierung",
        ),
        "phone" to listOf("phone", "telephone", "telefono", "cellulare", "mobile", "handy"),
        "entertain" to listOf(
            "entertainment", "intrattenimento", "divertimento", "cinema", "movies",
            "teatro", "concert", "unterhaltung", "loisir",
        ),
        "health" to listOf(
            "health", "healthcare", "salute", "benessere", "medico", "medical",
            "doctor", "farmacia", "dottore", "dentist", "dentista", "gesundheit",
            "sante", "santé",
        ),
        "fitness" to listOf("fitness", "gym", "palestra", "sport", "allenamento", "fitnessstudio"),
        "beauty" to listOf(
            "beauty", "personal", "care", "parrucchiere", "hairdresser", "haircut",
            "barber", "estetista", "bellezza", "cura", "schonheit", "schönheit",
        ),
        "gift" to listOf("gift", "gifts", "regali", "regalo", "dono", "geschenk", "cadeau"),
        "salary" to listOf(
            "salary", "salaries", "wage", "wages", "paycheck", "payroll", "stipendio",
            "salario", "retribuzione", "gehalt", "salaire",
        ),
        "invest" to listOf(
            "investment", "investments", "stocks", "dividends", "investimenti",
            "investimento", "borsa", "azioni", "investition",
        ),
        "house" to listOf(
            "house", "housing", "rent", "mortgage", "casa", "affitto", "mutuo", "haus",
            "miete", "maison", "loyer",
        ),
        "util" to listOf(
            "utilities", "bills", "bill", "bollette", "bolletta", "electricity", "luce",
            "water", "acqua", "heating", "strom", "nebenkosten",
        ),
        "edu" to listOf(
            "education", "school", "books", "tuition", "istruzione", "scuola",
            "universita", "università", "libri", "bildung", "ecole", "école",
        ),
        "pet" to listOf(
            "pets", "vet", "veterinary", "animali", "animale", "veterinario",
            "haustier", "veterinaire", "vétérinaire",
        ),
        "fees" to listOf("fees", "banking", "commissioni", "prelievo", "bancarie", "withdrawal"),
        "other" to listOf("other", "misc", "altro", "varie", "vario", "sonstiges", "autre", "otros"),
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
            // Prefix match so inflections the table doesn't list still work:
            // "utilities".startsWith("util") -> canonical "util".
            //
            // The 4-character floor is load-bearing, not tidiness. Short keys match far too much by
            // prefix alone — it is how "petrol" became `pet` and filed fuel under animals, and with
            // `gas` a key, "gastronomia" would go the same way. The three short keys (`gas`, `pet`,
            // `edu`) list their own inflections explicitly instead.
            //
            // `minOrNull` rather than `firstOrNull`: iOS sorts its keys here, and picking
            // alphabetically keeps the two platforms answering identically for a token that
            // prefix-matches more than one key.
            val canonical = synonymLookup[token]
                ?: synonyms.keys
                    .filter { it.length >= 4 && (token.startsWith(it) || it.startsWith(token)) }
                    .minOrNull()
            if (canonical != null) keys.add(canonical)
            keys.add(token)
        }
        return keys
    }

    /**
     * Exact name match — the one tier that cannot be wrong.
     *
     * A CSV category is often the app's own name with an emoji glued on ("🍕 Restaurants"), which
     * is exactly the file this flow is most often pointed at. Without stripping, the exact tier
     * never fires on such a file and every row falls through to guessing.
     */
    private fun exactMatch(csv: String, pool: List<FinanceCategory>): FinanceCategory? {
        pool.firstOrNull { it.name.equals(csv, ignoreCase = true) }?.let { return it }
        val stripped = csv.trim().dropWhile { !it.isLetterOrDigit() }.trim()
        if (stripped.isEmpty() || stripped == csv) return null
        return pool.firstOrNull { it.name.equals(stripped, ignoreCase = true) }
    }

    /** Keyword overlap, then a substring fallback. Both are guesses. */
    private fun heuristicMatch(csv: String, pool: List<FinanceCategory>): FinanceCategory? {
        val csvKeys = canonicalKeywords(csv)
        // Equal overlap -> shorter category name wins. Crude, but it is what picks "Education" over
        // "Books & Education", and the alternative is worse than crude: scoring with `overlap >
        // best` left ties to be settled by whichever category the caller happened to pass first, so
        // the same file could map differently from one screen to the next.
        val best = pool
            .map { it to csvKeys.intersect(canonicalKeywords(it.name)).size }
            .filter { it.second > 0 }
            .maxWithOrNull(compareBy({ it.second }, { -it.first.name.length }))
        if (best != null) return best.first

        val lower = csv.lowercase()
        return pool.firstOrNull { lower.contains(it.name.lowercase()) || it.name.lowercase().contains(lower) }
    }

    /**
     * 1. Exact name match (emoji-tolerant).
     * 2. Most-keyword-overlap match (multilingual synonyms, inflections via prefix match).
     * 3. Substring fallback.
     *
     * iOS has a tier between 1 and 2 that consults the user's own concept-to-category pairing from
     * Settings. Android has no equivalent screen yet, so there is nothing to consult here.
     */
    fun bestMatch(csv: String, pool: List<FinanceCategory>): FinanceCategory? =
        exactMatch(csv, pool) ?: heuristicMatch(csv, pool)
}
