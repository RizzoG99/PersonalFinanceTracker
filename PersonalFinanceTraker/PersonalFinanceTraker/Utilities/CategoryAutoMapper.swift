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
            selections[csv] = bestMatch(for: csv, in: pool)?.id.uuidString ?? newSentinel
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
    private static let synonyms: [String: [String]] = [
        "grocer":       ["spesa", "supermercato", "alimentari", "lebensmittel", "épicerie", "comestibles"],
        "restaurant":   ["ristorante", "colazione", "pranzo", "cena", "bar", "caffè", "trattoria",
                         "restaurant", "gaststätte", "comida"],
        "transport":    ["trasporti", "trasporto", "moto", "auto", "veicolo", "benzina", "carburante",
                         "treno", "bus", "metro", "transporte", "verkehr"],
        "travel":       ["viaggi", "viaggio", "vacanza", "esperienze", "hotel", "volo", "reise", "voyage"],
        "shopping":     ["acquisti", "acquisto", "vestiti", "abbigliamento", "einkauf", "achat"],
        "subscript":    ["abbonamenti", "abbonamento", "abonnement", "abonnierung"],
        "entertain":    ["intrattenimento", "divertimento", "cinema", "teatro", "unterhaltung", "loisir"],
        "health":       ["salute", "benessere", "medico", "farmacia", "dottore", "gesundheit", "santé"],
        "fitness":      ["palestra", "sport", "allenamento", "fitness", "fitnessstudio"],
        "beauty":       ["parrucchiere", "estetista", "bellezza", "cura", "schönheit"],
        "gift":         ["regali", "regalo", "dono", "geschenk", "cadeau"],
        "salary":       ["stipendio", "salario", "retribuzione", "gehalt", "salaire"],
        "invest":       ["investimenti", "investimento", "borsa", "azioni", "investition"],
        "house":        ["casa", "affitto", "mutuo", "haus", "miete", "maison", "loyer"],
        "util":         ["bollette", "bolletta", "luce", "gas", "acqua", "internet", "strom", "nebenkosten"],
        "edu":          ["istruzione", "scuola", "università", "libri", "bildung", "école"],
        "pet":          ["animali", "animale", "veterinario", "haustier", "vétérinaire"],
        "other":        ["altro", "varie", "vario", "sonstiges", "autre", "otros"],
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
                // Prefix match so English inflections work:
                // "groceries".hasPrefix("grocer") → canonical "grocer"
                if let canonical = synonyms.keys.first(where: {
                    token.hasPrefix($0) || $0.hasPrefix(token)
                }) {
                    keys.insert(canonical)
                }
            }
            keys.insert(token)
        }
        return keys
    }

    static func bestMatch(for csv: String, in pool: [CategorySnapshot]) -> CategorySnapshot? {
        // 1. Exact name match
        if let exact = pool.first(where: { $0.name.caseInsensitiveCompare(csv) == .orderedSame }) {
            return exact
        }
        let csvKeys = canonicalKeywords(for: csv)
        // 2. Most-keyword-overlap match
        var bestScore = 0
        var best: CategorySnapshot? = nil
        for cat in pool {
            let catKeys = canonicalKeywords(for: cat.name)
            let overlap = csvKeys.intersection(catKeys).count
            if overlap > bestScore {
                bestScore = overlap
                best = cat
            }
        }
        if bestScore > 0 { return best }
        // 3. Substring fallback
        let lower = csv.lowercased()
        return pool.first(where: {
            lower.contains($0.name.lowercased()) || $0.name.lowercased().contains(lower)
        })
    }
}
