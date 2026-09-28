import Testing
@testable import PersonalFinanceTraker
import Foundation

/// Everything that writes `ReceiptCategoryMap`'s single `UserDefaults` key lives under this one
/// serialized parent. As two sibling suites they ran concurrently on Xcode Cloud (the shared
/// scheme has parallelizable = "YES") and clobbered each other: `setCategoryId` rewrites the whole
/// dictionary, and `prune` deletes every pairing it wasn't handed. That failed build 99 on a test
/// nothing had touched. `.serialized` on each suite alone only orders tests *within* it —
/// `.serialized` on this parent applies recursively, so no two descendant tests run concurrently.
@Suite(.serialized)
struct ReceiptCategoryPairingTests {

    struct InferrerTests {

        /// A gelateria has no word in common with any category name, so before the keyword entries it
        /// fell through every tier to the most-used fallback — on a real device that produced
        /// "Banking Fees" for a €5 ice cream. The required field was filled with something actively
        /// wrong, which is worse than generic, because a wrong pick also teaches the learned tier.
        @Test func gelateriaMerchantsReachTheEatingOutCategory() async {
            let dining = CategorySnapshot.test(name: "Restaurant", type: .expense)
            let banking = CategorySnapshot.test(name: "Banking Fees", type: .expense)

            for merchant in ["Cremeria", "Gelateria Moscara", "Pasticceria Rossi"] {
                let result = await ReceiptCategoryInferrer.infer(
                    merchant: merchant,
                    merchantAddress: nil,
                    transactionType: .expense,
                    categories: [dining, banking],
                    learnedMerchants: [:],
                    // Banking Fees is the most-used, so the last-resort tier would pick it — this only
                    // passes if the keyword tier matched first.
                    usage: [banking.persistentId: 99]
                )
                #expect(result?.category.id == dining.id, "\(merchant) should not fall through to the fallback")
            }
        }

        /// Categories are user-created and user-renamed, so the name-based synonym matching cannot
        /// reach a category called something the synonym list has never heard of. The Settings pairing
        /// is the escape hatch, and it has to beat name matching rather than merely supplement it.
        @Test func settingsPairingBeatsNameMatchingForACategoryTheSynonymsCannotReach() async {
            let invented = CategorySnapshot.test(name: "Uscite varie", type: .expense)
            let restaurant = CategorySnapshot.test(name: "Restaurant", type: .expense)
            defer { ReceiptCategoryMap.setCategoryId(nil, for: .restaurant) }
            ReceiptCategoryMap.setCategoryId(invented.id, for: .restaurant)

            let result = await ReceiptCategoryInferrer.infer(
                merchant: "Cremeria",
                merchantAddress: nil,
                transactionType: .expense,
                // "Restaurant" would win on name alone; the user's explicit pairing must override it.
                categories: [invented, restaurant],
                learnedMerchants: [:],
                usage: [:]
            )

            #expect(result?.category.id == invented.id)
        }

        /// An unset concept must not swallow the automatic behaviour — the screen is optional.
        @Test func anUnsetPairingFallsBackToNameMatching() async {
            let restaurant = CategorySnapshot.test(name: "Restaurant", type: .expense)
            ReceiptCategoryMap.setCategoryId(nil, for: .restaurant)

            let result = await ReceiptCategoryInferrer.infer(
                merchant: "Cremeria",
                merchantAddress: nil,
                transactionType: .expense,
                categories: [restaurant],
                learnedMerchants: [:],
                usage: [:]
            )

            #expect(result?.category.id == restaurant.id)
        }

        /// A pairing pointing at a deleted category is worse than no pairing: it looks configured and
        /// behaves as unset. Pruning keeps the two states honest.
        @Test func pairingsForDeletedCategoriesArePruned() {
            let gone = CategorySnapshot.test(name: "Gelati", type: .expense)
            let kept = CategorySnapshot.test(name: "Food", type: .expense)
            ReceiptCategoryMap.setCategoryId(gone.id, for: .restaurant)
            ReceiptCategoryMap.setCategoryId(kept.id, for: .grocer)

            ReceiptCategoryMap.prune(against: [kept])

            #expect(ReceiptCategoryMap.categoryId(for: .restaurant) == nil)
            #expect(ReceiptCategoryMap.categoryId(for: .grocer) == kept.id)
            ReceiptCategoryMap.setCategoryId(nil, for: .grocer)
        }

        /// The fallback exists so a required field is never empty, but its answer is the user's habit,
        /// not anything the receipt said. Everything downstream depends on being able to tell the two
        /// apart, so the flag is asserted directly rather than inferred from which category came back.
        @Test func theMostUsedFallbackIsReportedAsAGuess() async {
            let food = CategorySnapshot.test(name: "Food", type: .expense)

            let result = await ReceiptCategoryInferrer.infer(
                // A merchant no tier can recognize: not learned, no keyword, no address for Maps.
                merchant: "ZZQ Trading 41",
                merchantAddress: nil,
                transactionType: .expense,
                categories: [food],
                learnedMerchants: [:],
                usage: [food.persistentId: 3]
            )

            #expect(result?.category.id == food.id)
            #expect(result?.isGuess == true)
        }

        /// The mirror of the above: a recognized merchant must *not* be flagged, or the warning becomes
        /// noise the user learns to ignore.
        @Test func arecognizedMerchantIsNotReportedAsAGuess() async {
            let health = CategorySnapshot.test(name: "Health", type: .expense)

            let result = await ReceiptCategoryInferrer.infer(
                merchant: "Farmacia Centrale",
                merchantAddress: nil,
                transactionType: .expense,
                categories: [health],
                learnedMerchants: [:],
                usage: [:]
            )

            #expect(result?.category.id == health.id)
            #expect(result?.isGuess == false)
        }

        @Test func learnedMappingWinsOverTheKeywordTable() async {
            // "Puce Motorrad" would keyword-match to a transport-ish category (see below), but this
            // merchant has already been corrected once to Vehicles — that correction must win.
            let transport = CategorySnapshot.test(name: "Vehicles", type: .expense)
            let other = CategorySnapshot.test(name: "Other", type: .expense)

            let result = await ReceiptCategoryInferrer.infer(
                merchant: "Puce Motorrad",
                merchantAddress: nil,
                transactionType: .expense,
                categories: [transport, other],
                learnedMerchants: [ReceiptCategoryInferrer.normalize("Puce Motorrad"): transport.id],
                usage: [:]
            )

            #expect(result?.category.id == transport.id)
        }

        @Test func learnedLookupIsCaseAndWhitespaceInsensitive() async {
            let health = CategorySnapshot.test(name: "Health", type: .expense)

            let result = await ReceiptCategoryInferrer.infer(
                merchant: "  FARMACIA CENTRALE  ",
                merchantAddress: nil,
                transactionType: .expense,
                categories: [health],
                learnedMerchants: ["farmacia centrale": health.id],
                usage: [:]
            )

            #expect(result?.category.id == health.id)
        }

        @Test func keywordFallbackMatchesMerchantBrandToAnExistingCategory() async {
            // No learned mapping yet. "moto" is a synonym CategoryAutoMapper already knows maps to
            // "transport" — reused rather than re-implemented.
            let transport = CategorySnapshot.test(name: "Trasporti", type: .expense)
            let groceries = CategorySnapshot.test(name: "Spesa", type: .expense)

            let result = await ReceiptCategoryInferrer.infer(
                merchant: "Puce Motorrad",
                merchantAddress: nil,
                transactionType: .expense,
                categories: [transport, groceries],
                learnedMerchants: [:],
                usage: [:]
            )

            #expect(result?.category.id == transport.id)
        }

        @Test func fallsBackToMostUsedCategoryWhenNothingMatches() async {
            // "Ottica Longo" hits no keyword in the table (no merchant directory covers opticians) —
            // this is the real case from the fixture receipts. No address either, so the MapKit tier
            // is skipped (its own early-return, not a network call) and this lands on tier 4. Category
            // is required, so it must still resolve to something rather than nil.
            let groceries = CategorySnapshot.test(name: "Spesa", type: .expense)
            let shopping = CategorySnapshot.test(name: "Shopping", type: .expense)

            let result = await ReceiptCategoryInferrer.infer(
                merchant: "Ottica Longo",
                merchantAddress: nil,
                transactionType: .expense,
                categories: [groceries, shopping],
                learnedMerchants: [:],
                usage: [groceries.persistentId: 1, shopping.persistentId: 5]
            )

            #expect(result?.category.id == shopping.id)
        }

        @Test func neverReturnsNilWhenAPoolExistsEvenWithNoMerchantAtAll() async {
            let onlyCategory = CategorySnapshot.test(name: "Other", type: .expense)

            let result = await ReceiptCategoryInferrer.infer(
                merchant: nil,
                merchantAddress: nil,
                transactionType: .expense,
                categories: [onlyCategory],
                learnedMerchants: [:],
                usage: [:]
            )

            #expect(result?.category.id == onlyCategory.id)
        }

        @Test func returnsNilWhenThereAreNoCategoriesOfThatTypeYet() async {
            let incomeOnly = CategorySnapshot.test(name: "Salary", type: .income)

            let result = await ReceiptCategoryInferrer.infer(
                merchant: "Conad",
                merchantAddress: nil,
                transactionType: .expense,
                categories: [incomeOnly],
                learnedMerchants: [:],
                usage: [:]
            )

            #expect(result == nil)
        }

        @Test func keywordMatchesAMerchantThatEndsExactlyWithTheKeyword() async {
            // Real-world miss: "Camilla-Nu Bar" ends with "bar" with nothing after it, so a naive
            // `contains("bar ")` (trailing-space keyword) never matches — this merchant fell through
            // to the most-used fallback instead of the correct "bar" category.
            let bar = CategorySnapshot.test(name: "Bar", type: .expense)
            let other = CategorySnapshot.test(name: "Other", type: .expense)

            let result = await ReceiptCategoryInferrer.infer(
                merchant: "Camilla-Nu Bar",
                merchantAddress: nil,
                transactionType: .expense,
                categories: [bar, other],
                learnedMerchants: [:],
                usage: [other.persistentId: 5]
            )

            #expect(result?.category.id == bar.id)
        }

        @Test func keywordFallbackRespectsTransactionType() async {
            // Two categories share a matchable name across types; only the Expense one should be
            // eligible when scanning an expense.
            let expenseGroceries = CategorySnapshot.test(name: "Spesa", type: .expense)
            let incomeGroceries = CategorySnapshot.test(name: "Spesa", type: .income)

            let result = await ReceiptCategoryInferrer.infer(
                merchant: "Conad Superstore",
                merchantAddress: nil,
                transactionType: .expense,
                categories: [expenseGroceries, incomeGroceries],
                learnedMerchants: [:],
                usage: [:]
            )

            #expect(result?.category.id == expenseGroceries.id)
        }

        @Test func noAddressSkipsTheMapKitTierWithoutHanging() async {
            // No address on the receipt at all — `MerchantCategoryLookup` must bail out on its own
            // guard before attempting any geocoding/network call, not hang waiting on one.
            let onlyCategory = CategorySnapshot.test(name: "Other", type: .expense)

            let result = await ReceiptCategoryInferrer.infer(
                merchant: "Barrueco S.R.L.",
                merchantAddress: nil,
                transactionType: .expense,
                categories: [onlyCategory],
                learnedMerchants: [:],
                usage: [:]
            )

            #expect(result?.category.id == onlyCategory.id)
        }
    }

    /// `resolve` is the import flow's entry point, and unlike `bestMatch` it consults the user's own
    /// concept → category pairing from Settings. Moved here (from `CategoryAutoMapperTests.swift`)
    /// because it shares the same `UserDefaults` key as `InferrerTests` above.
    struct ImportPairingTests {
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
}
