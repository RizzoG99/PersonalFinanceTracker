import Testing
@testable import PersonalFinanceTraker
import Foundation

@Suite
struct ReceiptCategoryInferrerTests {

    @Test func learnedMappingWinsOverTheKeywordTable() {
        // "Puce Motorrad" would keyword-match to a transport-ish category (see below), but this
        // merchant has already been corrected once to Vehicles — that correction must win.
        let transport = CategorySnapshot.test(name: "Vehicles", type: .expense)
        let other = CategorySnapshot.test(name: "Other", type: .expense)

        let result = ReceiptCategoryInferrer.infer(
            merchant: "Puce Motorrad",
            transactionType: .expense,
            categories: [transport, other],
            learnedMerchants: [ReceiptCategoryInferrer.normalize("Puce Motorrad"): transport.id],
            usage: [:]
        )

        #expect(result?.id == transport.id)
    }

    @Test func learnedLookupIsCaseAndWhitespaceInsensitive() {
        let health = CategorySnapshot.test(name: "Health", type: .expense)

        let result = ReceiptCategoryInferrer.infer(
            merchant: "  FARMACIA CENTRALE  ",
            transactionType: .expense,
            categories: [health],
            learnedMerchants: ["farmacia centrale": health.id],
            usage: [:]
        )

        #expect(result?.id == health.id)
    }

    @Test func keywordFallbackMatchesMerchantBrandToAnExistingCategory() {
        // No learned mapping yet. "moto" is a synonym CategoryAutoMapper already knows maps to
        // "transport" — reused rather than re-implemented.
        let transport = CategorySnapshot.test(name: "Trasporti", type: .expense)
        let groceries = CategorySnapshot.test(name: "Spesa", type: .expense)

        let result = ReceiptCategoryInferrer.infer(
            merchant: "Puce Motorrad",
            transactionType: .expense,
            categories: [transport, groceries],
            learnedMerchants: [:],
            usage: [:]
        )

        #expect(result?.id == transport.id)
    }

    @Test func fallsBackToMostUsedCategoryWhenNothingMatches() {
        // "Ottica Longo" hits no keyword in the table (no merchant directory covers opticians) —
        // this is the real case from the fixture receipts. Category is required, so it must still
        // resolve to something rather than nil.
        let groceries = CategorySnapshot.test(name: "Spesa", type: .expense)
        let shopping = CategorySnapshot.test(name: "Shopping", type: .expense)

        let result = ReceiptCategoryInferrer.infer(
            merchant: "Ottica Longo",
            transactionType: .expense,
            categories: [groceries, shopping],
            learnedMerchants: [:],
            usage: [groceries.persistentId: 1, shopping.persistentId: 5]
        )

        #expect(result?.id == shopping.id)
    }

    @Test func neverReturnsNilWhenAPoolExistsEvenWithNoMerchantAtAll() {
        let onlyCategory = CategorySnapshot.test(name: "Other", type: .expense)

        let result = ReceiptCategoryInferrer.infer(
            merchant: nil,
            transactionType: .expense,
            categories: [onlyCategory],
            learnedMerchants: [:],
            usage: [:]
        )

        #expect(result?.id == onlyCategory.id)
    }

    @Test func returnsNilWhenThereAreNoCategoriesOfThatTypeYet() {
        let incomeOnly = CategorySnapshot.test(name: "Salary", type: .income)

        let result = ReceiptCategoryInferrer.infer(
            merchant: "Conad",
            transactionType: .expense,
            categories: [incomeOnly],
            learnedMerchants: [:],
            usage: [:]
        )

        #expect(result == nil)
    }

    @Test func keywordMatchesAMerchantThatEndsExactlyWithTheKeyword() {
        // Real-world miss: "Camilla-Nu Bar" ends with "bar" with nothing after it, so a naive
        // `contains("bar ")` (trailing-space keyword) never matches — this merchant fell through
        // to the most-used fallback instead of the correct "bar" category.
        let bar = CategorySnapshot.test(name: "Bar", type: .expense)
        let other = CategorySnapshot.test(name: "Other", type: .expense)

        let result = ReceiptCategoryInferrer.infer(
            merchant: "Camilla-Nu Bar",
            transactionType: .expense,
            categories: [bar, other],
            learnedMerchants: [:],
            usage: [other.persistentId: 5]
        )

        #expect(result?.id == bar.id)
    }

    @Test func keywordFallbackRespectsTransactionType() {
        // Two categories share a matchable name across types; only the Expense one should be
        // eligible when scanning an expense.
        let expenseGroceries = CategorySnapshot.test(name: "Spesa", type: .expense)
        let incomeGroceries = CategorySnapshot.test(name: "Spesa", type: .income)

        let result = ReceiptCategoryInferrer.infer(
            merchant: "Conad Superstore",
            transactionType: .expense,
            categories: [expenseGroceries, incomeGroceries],
            learnedMerchants: [:],
            usage: [:]
        )

        #expect(result?.id == expenseGroceries.id)
    }
}
