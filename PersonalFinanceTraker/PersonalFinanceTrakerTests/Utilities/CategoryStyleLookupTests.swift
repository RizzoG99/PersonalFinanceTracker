import Testing
import SwiftUI
@testable import PersonalFinanceTraker

/// Name-only rows (upcoming charges, trip breakdown, habit streaks) match the saved category (#249).
struct CategoryStyleLookupTests {

    private func snapshot(_ name: String, _ icon: String, _ color: String, _ type: TransactionType) -> CategorySnapshot {
        CategorySnapshot(CategoryModel(name: name, systemImage: icon, type: type, colorToken: color))
    }

    @Test func savedCategoryWinsOverTheNameGuess() {
        let lookup = CategoryStyleLookup([snapshot("Groceries", "cart.fill", "categoryOrange", .expense)])
        let info = lookup.info(for: "Groceries", type: .expense)
        #expect(info.color == Color(categoryToken: "categoryOrange"))
        #expect(info.symbol == "cart.fill")
        // The keyword guess alone would say green, the income color.
        #expect(CategoryInfo.info(for: "Groceries").color != info.color)
    }

    @Test func sameNameInTheOtherTypeIsKeptApart() {
        let lookup = CategoryStyleLookup([
            snapshot("Other", "ellipsis.circle.fill", "categoryGray", .expense),
            snapshot("Other", "star.fill", "categoryAmber", .income),
        ])
        #expect(lookup.info(for: "Other", type: .expense).symbol == "ellipsis.circle.fill")
        #expect(lookup.info(for: "Other", type: .income).symbol == "star.fill")
    }

    @Test func unknownNameFallsBackToTheKeywordGuess() {
        let lookup = CategoryStyleLookup([])
        let info = lookup.info(for: "Groceries", type: .expense)
        #expect(info.symbol == CategoryInfo.info(for: "Groceries").symbol)
        #expect(info.color == CategoryInfo.info(for: "Groceries").color)
    }

    @Test func nameFromTheOtherTypeDoesNotMatch() {
        let lookup = CategoryStyleLookup([snapshot("Gift", "gift.fill", "categoryPink", .income)])
        #expect(lookup.info(for: "Gift", type: .expense).color == CategoryInfo.info(for: "Gift").color)
    }
}
