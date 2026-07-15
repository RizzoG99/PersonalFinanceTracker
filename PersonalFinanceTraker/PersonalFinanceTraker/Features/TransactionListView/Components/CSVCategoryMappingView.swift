//
//  CSVCategoryMappingView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CSVCategoryMappingView: View {
    let csvCategories: [String]
    /// Inferred income/expense type for each CSV category. Nil = unknown (show all).
    let categoryTypes: [String: TransactionType]
    let availableCategories: [CategorySnapshot]
    @Binding var selections: [String: String]
    let currentStep: Int
    let totalSteps: Int
    let onContinue: () -> Void

    @Environment(TransactionListViewModel.self) private var viewModel

    private let newSentinel = "__new__"

    private var allMapped: Bool {
        csvCategories.allSatisfy { selections[$0] != nil }
    }

    private var unmappedCount: Int {
        csvCategories.filter { selections[$0] == nil }.count
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Map each CSV category to an existing app category, or create a new one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Auto-Map All") { autoMap() }
                        .font(.subheadline.bold())
                }
                .padding(.vertical, 4)
            } footer: {
                if !allMapped {
                    Text("Map all \(unmappedCount) remaining categor\(unmappedCount == 1 ? "y" : "ies") to continue.")
                        .foregroundStyle(.red)
                }
            }
            .appFormSectionBackground()

            let expenseCategories = csvCategories.filter { categoryTypes[$0] != .income }
            let incomeCategories  = csvCategories.filter { categoryTypes[$0] == .income }

            if !expenseCategories.isEmpty {
                Section("Expenses") {
                    ForEach(expenseCategories, id: \.self) { csv in
                        categoryRow(for: csv)
                    }
                }
                .appFormSectionBackground()
            }
            if !incomeCategories.isEmpty {
                Section("Income") {
                    ForEach(incomeCategories, id: \.self) { csv in
                        categoryRow(for: csv)
                    }
                }
                .appFormSectionBackground()
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Map Categories")
        .navigationSubtitle("Step \(currentStep) of \(totalSteps)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Continue") { buildResolutionAndContinue() }
                    .bold()
                    .disabled(!allMapped)
            }
        }
        .onAppear {
            // Auto-map on first appear only (guard against re-running on back-nav)
            if !viewModel.hasAutoMappedCategories {
                autoMap()
                viewModel.hasAutoMappedCategories = true
            }
        }
    }

    // MARK: - Row

    private func categoryRow(for csv: String) -> some View {
        let displayName = csv.removingLeadingEmoji.isEmpty ? "\(csv) (unnamed)" : csv
        return HStack {
            Text(displayName)
                .font(.subheadline)

            Spacer()

            Menu {
                let knownType = categoryTypes[csv]
                let filtered = filteredCategories(for: knownType).sorted { $0.name < $1.name }

                if knownType == nil {
                    // Type unknown — show both sections
                    let income  = filtered.filter { $0.transactionType == .income }
                    let expense = filtered.filter { $0.transactionType == .expense }
                    if !income.isEmpty {
                        Section("Income") {
                            ForEach(income) { cat in
                                Button { selections[csv] = cat.id.uuidString } label: {
                                    Label(cat.name, systemImage: cat.systemImage)
                                }
                            }
                        }
                    }
                    if !expense.isEmpty {
                        Section("Expense") {
                            ForEach(expense) { cat in
                                Button { selections[csv] = cat.id.uuidString } label: {
                                    Label(cat.name, systemImage: cat.systemImage)
                                }
                            }
                        }
                    }
                } else {
                    // Type known — flat sorted list
                    ForEach(filtered) { cat in
                        Button { selections[csv] = cat.id.uuidString } label: {
                            Label(cat.name, systemImage: cat.systemImage)
                        }
                    }
                }
                Divider()
                Button {
                    selections[csv] = newSentinel
                } label: {
                    Label("Create \"\(csv.removingLeadingEmoji.trimmingCharacters(in: .whitespaces))\"", systemImage: "plus.circle")
                }
            } label: {
                HStack(spacing: 4) {
                    if let sel = selections[csv] {
                        if sel == newSentinel {
                            Text("New")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                        } else if let cat = availableCategories.first(where: { $0.id.uuidString == sel }) {
                            Text(cat.name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Text("Select…")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    /// Returns categories filtered to the matching type, or all if type is unknown.
    private func filteredCategories(for type: TransactionType?) -> [CategorySnapshot] {
        guard let type else { return availableCategories }
        return availableCategories.filter { $0.transactionType == type }
    }

    // MARK: - Actions

    private func autoMap() {
        for csv in csvCategories {
            if selections[csv] != nil { continue }
            let type = categoryTypes[csv]
            let pool = filteredCategories(for: type)
            if let match = bestMatch(for: csv, in: pool) {
                selections[csv] = match.id.uuidString
            } else {
                selections[csv] = newSentinel
            }
        }
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

    /// Returns the canonical keyword set for a given string (CSV category or app category name).
    private func canonicalKeywords(for text: String) -> Set<String> {
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        var keys = Set<String>()
        for token in tokens {
            if let canonical = Self.synonymLookup[token] {
                // Direct synonym hit: "spesa" → "grocer"
                keys.insert(canonical)
            } else {
                // Prefix match so English inflections work:
                // "groceries".hasPrefix("grocer") → canonical "grocer"
                if let canonical = Self.synonyms.keys.first(where: {
                    token.hasPrefix($0) || $0.hasPrefix(token)
                }) {
                    keys.insert(canonical)
                }
            }
            keys.insert(token)
        }
        return keys
    }

    private func bestMatch(for csv: String, in pool: [CategorySnapshot]) -> CategorySnapshot? {
        // 1. Exact name match
        if let exact = pool.first(where: { $0.name.caseInsensitiveCompare(csv) == .orderedSame }) {
            return exact
        }
        let csvKeys = canonicalKeywords(for: csv)
        // 2. Most-keyword-overlap match
        var bestScore = 0
        var bestMatch: CategorySnapshot? = nil
        for cat in pool {
            let catKeys = canonicalKeywords(for: cat.name)
            let overlap = csvKeys.intersection(catKeys).count
            if overlap > bestScore {
                bestScore = overlap
                bestMatch = cat
            }
        }
        if bestScore > 0 { return bestMatch }
        // 3. Substring fallback
        let lower = csv.lowercased()
        return pool.first(where: {
            lower.contains($0.name.lowercased()) || $0.name.lowercased().contains(lower)
        })
    }

    private func buildResolutionAndContinue() {
        // Selections already contain the choices (UUID strings or newSentinel).
        // Actual category creation happens in confirmImport; nothing to do here except continue.
        onContinue()
    }
}
