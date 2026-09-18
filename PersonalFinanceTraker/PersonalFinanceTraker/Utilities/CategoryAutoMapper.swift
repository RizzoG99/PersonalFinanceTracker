//
//  CategoryAutoMapper.swift
//  PersonalFinanceTraker
//

import Foundation

/// Matches CSV category names against the app's own categories, across languages.
///
/// Lifted out of `CSVCategoryMappingView` unchanged: the iPad import shows a live preview of mapped
/// rows before the user ever opens the category tab, so the auto-mapping has to be callable without
/// a view on screen. Two copies of this matching would drift, and the wrong copy winning would
/// silently re-file people's spending.
enum CategoryAutoMapper {
    /// Marks "create a new category with the CSV's own name" — the same sentinel the picker stores.
    static let newSentinel = "__new__"

    /// Fills in a selection for every CSV category that doesn't have one yet. Existing entries are
    /// never overwritten: a manual choice outranks a guess.
    static func resolve(
        csvCategories: [String],
        categoryTypes: [String: TransactionType],
        availableCategories: [CategorySnapshot],
        existing: [String: String]
    ) -> [String: String] {
        var selections = existing
        for csv in csvCategories where selections[csv] == nil {
            let pool = pool(for: categoryTypes[csv], in: availableCategories)
            // Three tiers rather than `bestMatch`, so the user's own concept → category pairing
            // from Settings sits between the two guesses: it outranks every heuristic below it,
            // and only an exact name match — which cannot be wrong — outranks it. The receipt
            // scanner has always honoured that pairing (`ReceiptCategoryInferrer.resolve`); the
            // importer ignoring it meant the two features disagreed about the same stated choice.
            let match = exactMatch(for: csv, in: pool)
                ?? ReceiptCategoryMap.category(forKeyword: csv, in: pool)
                ?? heuristicMatch(for: csv, in: pool)
            selections[csv] = match?.id.uuidString ?? newSentinel
        }
        return selections
    }

    static func pool(
        for type: TransactionType?,
        in availableCategories: [CategorySnapshot]
    ) -> [CategorySnapshot] {
        guard let type else { return availableCategories }
        return availableCategories.filter { $0.transactionType == type }
    }

    // MARK: - Multilingual matching

    /// Maps canonical keyword → synonyms in multiple languages.
    ///
    /// Two rules keep this table honest, both learned the hard way:
    ///
    /// 1. **Every word belongs to exactly one key.** `synonymLookup` flattens this with
    ///    last-write-wins, and Swift's dictionary iteration order is randomized per process, so a
    ///    word listed twice gets a different owner on different launches. `CategoryAutoMapperTests`
    ///    asserts there are no duplicates.
    /// 2. **Each key lists its own name plus the words of the app category it should reach.** The
    ///    table used to be one-sided — foreign word → stem — while the app's category names were
    ///    only ever tokenized raw. So "affitto" resolved to the stem `house` and then matched
    ///    nothing, because the category is called "Rent/Mortgage". Matching worked only where the
    ///    English label happened to contain the stem ("Groceries" ⊃ "grocer"). The reverse entries
    ///    ("rent", "mortgage" under `house`) are what close that loop.
    ///
    /// Corollary to rule 2: a word that is itself a distinct category label must *not* be listed
    /// under a broader concept, or the narrow label steals the broad concept's matches — "internet"
    /// under `util` made "Bollette" resolve to the Internet category instead of Utilities, and
    /// "pharmacy" under `health` sent "Doctor" to Pharmacy. Both reach their own category by exact
    /// name anyway.
    ///
    /// Accents are handled as data, not logic: both spellings are listed, which is cheaper and more
    /// predictable than folding diacritics in the tokenizer.
    /// Internal rather than private so `CategoryAutoMapperTests` can assert rule 1 against the real
    /// table instead of a hand-copied duplicate of it.
    static let synonyms: [String: [String]] = [
        "grocer":       ["grocer", "groceries", "supermarket", "spesa", "supermercato", "alimentari",
                         "lebensmittel", "epicerie", "épicerie", "comestibles"],
        "restaurant":   ["restaurant", "restaurants", "ristorante", "ristoranti", "dining", "eating",
                         "pizzeria", "colazione", "pranzo", "cena", "bar", "trattoria",
                         "gaststatte", "gaststätte", "comida"],
        // Split out of `restaurant` so "Caffè" reaches "Coffee & Drinks". "bar" deliberately stays
        // with the restaurants: ReceiptCategoryInferrer maps gelaterie and pasticcerie to it, and
        // moving it would re-route those receipts (see the note on its merchantKeywords table).
        "coffee":       ["coffee", "cafe", "caffe", "caffè", "kaffee"],
        "transport":    ["transport", "public", "commute", "trasporti", "trasporto", "transporte",
                         "verkehr", "treno", "train", "bus", "metro", "parking", "parcheggio",
                         "auto", "veicolo", "moto"],
        // Split out of `transport` so fuel reaches "Gas" rather than "Public Transport". This also
        // takes "gas" away from `util`, which is why an Italian gas *bill* now reads as fuel —
        // ambiguous either way, and no worse than before, when it landed on "Gas" regardless via an
        // order-dependent tie.
        "gas":          ["gas", "benzina", "carburante", "petrol", "fuel", "diesel", "gasolio",
                         "essence", "kraftstoff"],
        "travel":       ["travel", "viaggi", "viaggio", "vacanza", "vacation", "holiday",
                         "esperienze", "hotel", "volo", "flight", "reise", "voyage"],
        "shopping":     ["shopping", "acquisti", "acquisto", "einkauf", "achat"],
        // Split out of `shopping`: the app has both a "Shopping" and a "Clothing" category.
        "cloth":        ["cloth", "clothing", "clothes", "vestiti", "abbigliamento", "kleidung",
                         "vetements", "vêtements", "ropa"],
        "subscript":    ["subscription", "subscriptions", "streaming", "abbonamenti", "abbonamento",
                         "abonnement", "abonnierung"],
        "phone":        ["phone", "telephone", "telefono", "cellulare", "mobile", "handy"],
        "entertain":    ["entertainment", "intrattenimento", "divertimento", "cinema", "movies",
                         "teatro", "concert", "unterhaltung", "loisir"],
        "health":       ["health", "healthcare", "salute", "benessere", "medico", "medical",
                         "doctor", "farmacia", "dottore", "dentist", "dentista", "gesundheit",
                         "sante", "santé"],
        "fitness":      ["fitness", "gym", "palestra", "sport", "allenamento", "fitnessstudio"],
        "beauty":       ["beauty", "personal", "care", "parrucchiere", "hairdresser", "haircut",
                         "barber", "estetista", "bellezza", "cura", "schonheit", "schönheit"],
        "gift":         ["gift", "gifts", "regali", "regalo", "dono", "geschenk", "cadeau"],
        "salary":       ["salary", "salaries", "wage", "wages", "paycheck", "payroll", "stipendio",
                         "salario", "retribuzione", "gehalt", "salaire"],
        "invest":       ["investment", "investments", "stocks", "dividends", "investimenti",
                         "investimento", "borsa", "azioni", "investition"],
        "house":        ["house", "housing", "rent", "mortgage", "casa", "affitto", "mutuo", "haus",
                         "miete", "maison", "loyer"],
        "util":         ["utilities", "bills", "bill", "bollette", "bolletta", "electricity", "luce",
                         "water", "acqua", "heating", "strom", "nebenkosten"],
        "edu":          ["education", "school", "books", "tuition", "istruzione", "scuola",
                         "universita", "università", "libri", "bildung", "ecole", "école"],
        "pet":          ["pets", "vet", "veterinary", "animali", "animale", "veterinario",
                         "haustier", "veterinaire", "vétérinaire"],
        "fees":         ["fees", "banking", "commissioni", "prelievo", "bancarie", "withdrawal"],
        "other":        ["other", "misc", "altro", "varie", "vario", "sonstiges", "autre", "otros"],
    ]

    /// Canonical keyword → set of synonyms (flattened, lowercased, pre-built once).
    private static let synonymLookup: [String: String] = {
        var map: [String: String] = [:]
        for (canonical, words) in synonyms {
            for word in words { map[word] = canonical }
        }
        return map
    }()

    /// The single canonical concept a keyword belongs to, e.g. "ristorante" → "restaurant".
    /// Filtered to real canonical keys: `canonicalKeywords` also returns the raw tokens it was
    /// given, so "bar" would otherwise answer "bar" (it sorts before "restaurant") instead of the
    /// concept it belongs to. Sorted rather than `.first` on the set so the answer is stable.
    static func canonicalConcept(for text: String) -> String? {
        canonicalKeywords(for: text).filter { synonyms.keys.contains($0) }.sorted().first
    }

    /// Returns the canonical keyword set for a given string (CSV category or app category name).
    private static func canonicalKeywords(for text: String) -> Set<String> {
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        var keys = Set<String>()
        for token in tokens {
            if let canonical = synonymLookup[token] {
                // Direct synonym hit: "spesa" → "grocer"
                keys.insert(canonical)
            } else {
                // Prefix match so inflections the table doesn't list still work:
                // "utilities".hasPrefix("util") → canonical "util".
                //
                // Sorted rather than `.first(where:)`: `synonyms.keys` is unordered and Swift
                // randomizes dictionary iteration per process, so a token matching two keys picked
                // a different winner on every launch.
                //
                // The 4-character floor is load-bearing, not tidiness. Short keys match far too
                // much by prefix alone — it is how "petrol" became `pet` and filed fuel under
                // animals, and with `gas` now a key "gastronomia" would go the same way. The three
                // short keys (`gas`, `pet`, `edu`) list their own inflections explicitly instead.
                if let canonical = synonyms.keys.filter({
                    $0.count >= 4 && (token.hasPrefix($0) || $0.hasPrefix(token))
                }).sorted().first {
                    keys.insert(canonical)
                }
            }
            keys.insert(token)
        }
        return keys
    }

    /// Exact name match — the one tier that cannot be wrong. Kept separate from the guesses below
    /// so `resolve` can slot the user's own Settings pairing between them.
    static func exactMatch(for csv: String, in pool: [CategorySnapshot]) -> CategorySnapshot? {
        if let exact = pool.first(where: { $0.name.caseInsensitiveCompare(csv) == .orderedSame }) {
            return exact
        }
        // A CSV category is often the app's own name with an emoji glued on ("🍕 Restaurants"),
        // which is exactly the file this flow is most often pointed at. Without this the exact
        // tier never fires on such a file and every row falls through to guessing.
        let stripped = csv.removingLeadingEmoji.trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty, stripped != csv else { return nil }
        return pool.first { $0.name.caseInsensitiveCompare(stripped) == .orderedSame }
    }

    /// Keyword overlap, then a substring fallback. Both are guesses.
    static func heuristicMatch(for csv: String, in pool: [CategorySnapshot]) -> CategorySnapshot? {
        let csvKeys = canonicalKeywords(for: csv)
        // ponytail: equal overlap → shorter category name wins. Crude, but it is what picks
        // "Education" over "Books & Education", and the alternative is worse than crude: the old
        // `overlap > bestScore` left ties to be settled by whichever category the caller happened
        // to pass first, so the same file could map differently from one screen to the next.
        let scored = pool
            .map { ($0, csvKeys.intersection(canonicalKeywords(for: $0.name)).count) }
            .filter { $0.1 > 0 }
        if let best = scored.max(by: { ($0.1, -$0.0.name.count) < ($1.1, -$1.0.name.count) }) {
            return best.0
        }
        let lower = csv.lowercased()
        return pool.first(where: {
            lower.contains($0.name.lowercased()) || $0.name.lowercased().contains(lower)
        })
    }

    /// Name matching only, in tier order. `resolve` does not use this — it inserts the user's
    /// explicit pairing in the middle — but `ReceiptCategoryInferrer` does, and consults that
    /// pairing itself beforehand.
    static func bestMatch(for csv: String, in pool: [CategorySnapshot]) -> CategorySnapshot? {
        exactMatch(for: csv, in: pool) ?? heuristicMatch(for: csv, in: pool)
    }
}
