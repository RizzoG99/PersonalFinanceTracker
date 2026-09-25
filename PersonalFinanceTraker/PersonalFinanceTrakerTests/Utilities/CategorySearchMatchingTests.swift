import Testing
import Foundation
@testable import PersonalFinanceTraker

/// One predicate now serves every category search box (#150). These cover the two storage
/// shapes it has to handle — `TransactionModel.category` keeps the emoji prefix,
/// `CategoryModel.name` does not — because a copy that handled only one of them is exactly
/// how this shipped broken twice.
@Suite struct CategorySearchMatchingTests {

    @Test func matchesTheRawStoredKeyWithAndWithoutEmoji() {
        #expect("🛒 Groceries".matchesCategorySearch("grocer"))
        #expect("Groceries".matchesCategorySearch("grocer"))
    }

    @Test func doesNotMatchAnUnrelatedCategory() {
        #expect(!"🚗 Transport".matchesCategorySearch("grocer"))
    }

    @Test func ignoresDiacritics() {
        #expect("Perché".matchesCategorySearch("perche"))
    }

    /// Only meaningful in a localized run: `scripts/xcb test -testLanguage it`.
    /// A condition trait, not an early `return`, so an English run reports *skipped* rather
    /// than a green pass that asserted nothing.
    @Test(.enabled(if: "Groceries".localizedCategoryDisplay != "Groceries"))
    func matchesTheLocalizedNameForBothStorageShapes() {
        let shown = "Groceries".localizedCategoryDisplay      // "Spesa" in Italian
        // The emoji-prefixed shape is the one that regressed: localizedCategoryDisplay is a
        // literal catalog lookup, so without the strip the key never matches.
        #expect("🛒 Groceries".matchesCategorySearch(shown.lowercased()))
        #expect("Groceries".matchesCategorySearch(shown.lowercased()))
    }
}
