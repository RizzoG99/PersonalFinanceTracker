import Testing
@testable import PersonalFinanceTraker

struct CategoryAutoMapperTests {
    // Regression for #47: an Income "Other" must be offered instead of falling through to
    // "__new__" — that's what makes the import flow stop prompting to create a duplicate.
    @Test("Auto-map offers the existing Income Other instead of prompting to create one")
    func resolvesAltroToExistingIncomeOther() {
        let expenseOther = CategorySnapshot.test(name: "Other", type: .expense)
        let incomeOther = CategorySnapshot.test(name: "Other", type: .income)

        let selections = CategoryAutoMapper.resolve(
            csvCategories: ["Altro"],
            categoryTypes: ["Altro": .income],
            availableCategories: [expenseOther, incomeOther],
            existing: [:]
        )

        #expect(selections["Altro"] == incomeOther.id.uuidString)
        #expect(selections["Altro"] != CategoryAutoMapper.newSentinel)
    }

    /// The synonym table is flattened into a lookup with last-write-wins, and Swift randomizes
    /// dictionary iteration per process — so a word listed under two keys resolves to a different
    /// concept on different launches. That is not a bug you can reproduce; it has to be prevented.
    @Test("No word appears under two canonical keys")
    func synonymsAreUnambiguous() {
        var owner: [String: String] = [:]
        var duplicates: [String] = []
        for (key, words) in CategoryAutoMapper.synonyms {
            for word in words {
                if let existing = owner[word] {
                    duplicates.append("\(word): \(existing) & \(key)")
                }
                owner[word] = key
            }
        }
        #expect(duplicates.isEmpty, "words with two owners: \(duplicates.sorted())")
    }

    /// The pool the app actually seeds (`SampleData.createSampleCategories` copies these labels
    /// verbatim into `CategoryModel.name`), so these expectations are what a real user sees.
    private static let expensePool = TransactionCategory.expenseCategories.map {
        CategorySnapshot.test(name: $0.label, type: .expense)
    }

    /// Every row here was a failure before the table was filled in: either a silent misfile
    /// ("Petrol" → Pets, "Bollette" → Gas) or a needless "create a new category" prompt.
    @Test("Auto-map lands CSV category names on the right seeded category", arguments: [
        // Italian — the language the table was originally written for.
        ("Spesa", "Groceries"),
        ("Ristoranti", "Restaurants"),          // plural; the table only had "ristorante"
        ("Benzina", "Gas"),                     // was Public Transport
        ("Carburante", "Gas"),                  // was Public Transport
        ("Affitto", "Rent/Mortgage"),           // was __new__: stem `house`, label says "Rent"
        ("Bollette", "Utilities"),              // was Gas, via an order-dependent tie
        ("Farmacia", "Healthcare"),
        ("Palestra", "Gym & Fitness"),
        ("Abbonamenti", "Streaming Services"),  // was __new__
        ("Animali", "Pets"),
        ("Trasporti", "Public Transport"),
        ("Viaggi", "Travel"),
        ("Istruzione", "Education"),            // was Books & Education
        ("Parrucchiere", "Personal Care"),      // was __new__: stem `beauty`
        ("Telefono", "Phone Bill"),             // was __new__
        ("Prelievo contante", "Banking Fees"),  // was __new__
        ("Vestiti", "Clothing"),                // was Shopping
        ("Altro", "Other"),
        // English — the table had almost no English in it, so most of these were __new__.
        ("Petrol", "Gas"),                      // was Pets: "petrol".hasPrefix("pet")
        ("Fuel", "Gas"),
        ("Rent", "Rent/Mortgage"),
        ("Mortgage", "Rent/Mortgage"),
        ("Bills", "Utilities"),
        ("Dining out", "Restaurants"),
        ("Eating out", "Restaurants"),
        ("Coffee", "Coffee & Drinks"),
        ("Car", "Car Maintenance"),
        ("Train", "Public Transport"),
        ("Parking", "Public Transport"),
        ("Subscriptions", "Streaming Services"),
        ("Haircut", "Personal Care"),
        ("Doctor", "Healthcare"),
        ("Vet", "Pets"),
        ("Gym", "Gym & Fitness"),
        ("Utilities Bill", "Utilities"),
    ])
    func mapsNameToSeededCategory(csvName: String, expected: String) {
        let match = CategoryAutoMapper.bestMatch(for: csvName, in: Self.expensePool)
        #expect(match?.name == expected, "\(csvName) → \(match?.name ?? "__new__")")
    }

    /// A category the app has no answer for must stay unmatched. Guessing here is worse than
    /// prompting: the user gets a wrong mapping that looks exactly as settled as a right one.
    @Test("Unknown categories stay unmatched", arguments: ["Insurance", "Taxes", "Netflix"])
    func leavesUnknownCategoriesUnmatched(csvName: String) {
        #expect(CategoryAutoMapper.bestMatch(for: csvName, in: Self.expensePool) == nil)
    }

    // Bank exports routinely prefix the app's own category names with an emoji, which is exactly
    // the shape of file this flow is pointed at most often. Without stripping, the exact tier never
    // fires and every row falls through to guessing.
    @Test("An emoji-prefixed name still matches the category exactly")
    func matchesThroughLeadingEmoji() {
        let match = CategoryAutoMapper.bestMatch(for: "🍕 Restaurants", in: Self.expensePool)
        #expect(match?.name == "Restaurants")
    }
}

/// `resolve` is the import flow's entry point, and unlike `bestMatch` it consults the user's own
/// concept → category pairing from Settings. Serialized and restoring the key afterwards because
/// `ReceiptCategoryMap` reads and writes `UserDefaults.standard` with no injection seam.
@Suite(.serialized)
struct CategoryAutoMapperUserPairingTests {
    /// A category no keyword in the table can reach — which is the whole reason the pairing exists.
    private let gelati = CategorySnapshot.test(name: "Gelati", type: .expense)
    private let groceries = CategorySnapshot.test(name: "Groceries", type: .expense)

    private func withPairing(_ concept: ReceiptCategoryConcept,
                             to category: CategorySnapshot?,
                             _ body: () -> Void) {
        let previous = ReceiptCategoryMap.categoryId(for: concept)
        ReceiptCategoryMap.setCategoryId(category?.id, for: concept)
        body()
        ReceiptCategoryMap.setCategoryId(previous, for: concept)
    }

    @Test("The user's own pairing beats the keyword heuristic")
    func userPairingOutranksHeuristic() {
        withPairing(.grocer, to: gelati) {
            let selections = CategoryAutoMapper.resolve(
                csvCategories: ["Spesa"],
                categoryTypes: ["Spesa": .expense],
                availableCategories: [groceries, gelati],
                existing: [:]
            )
            // Without the tier this resolves to "Groceries" — a defensible guess that nonetheless
            // overrides something the user stated outright.
            #expect(selections["Spesa"] == gelati.id.uuidString)
        }
    }

    @Test("An exact name match still beats the user's pairing")
    func exactMatchOutranksUserPairing() {
        withPairing(.grocer, to: gelati) {
            let selections = CategoryAutoMapper.resolve(
                csvCategories: ["Groceries"],
                categoryTypes: ["Groceries": .expense],
                availableCategories: [groceries, gelati],
                existing: [:]
            )
            #expect(selections["Groceries"] == groceries.id.uuidString)
        }
    }
}
