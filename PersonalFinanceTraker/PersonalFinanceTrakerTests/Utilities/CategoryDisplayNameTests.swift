//
//  CategoryDisplayNameTests.swift
//  PersonalFinanceTrakerTests
//
//  #239: built-in categories are stored under English keys and translated only for display.
//  The Italian-only assertions are gated with `.enabled(if:)`, so an English run reports them
//  as skipped rather than passed. Run them with:
//  scripts/xcb test -testLanguage it -testRegion IT -only-testing:PersonalFinanceTrakerTests/CategoryDisplayNameTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

struct CategoryDisplayNameTests {

    static let isTranslated = "Groceries".localizedCategoryDisplay != "Groceries"

    private func pace(_ category: String) -> CycleSummary.CategoryPace {
        CycleSummary.CategoryPace(category: category, spent: 10, delta: 0)
    }

    // MARK: - Edit sheet: only a real change becomes a rename (any language)

    @Test func untouchedNameIsNotARename() {
        #expect(CategoryNameValidator.renamedName(stored: "Groceries", edited: "Groceries".localizedCategoryDisplay) == nil)
        #expect(CategoryNameValidator.renamedName(stored: "Psicologa", edited: "  Psicologa ") == nil)
    }

    @Test func changedNameIsTrimmed() {
        #expect(CategoryNameValidator.renamedName(stored: "Psicologa", edited: " Terapia ") == "Terapia")
    }

    @Test func customNamesPassThroughUntranslated() {
        #expect(pace("Psicologa").displayName == "Psicologa")
    }

    // MARK: - Italian

    /// The bug this guards: saving an untouched built-in stored "Spesa" over the "Groceries"
    /// key, so the category stopped following the app language.
    @Test(.enabled(if: isTranslated)) func untouchedTranslatedNameKeepsTheKey() {
        #expect(CategoryNameValidator.renamedName(stored: "Groceries", edited: "Spesa") == nil)
        #expect(CategoryNameValidator.renamedName(stored: "Groceries", edited: "Spesa casa") == "Spesa casa")
    }

    /// "This cycle" list and the Home card's "Mostly X and Y" both read `displayName`.
    @Test(.enabled(if: isTranslated)) func cyclePaceShowsTranslatedName() {
        #expect(pace("Healthcare").displayName == "Sanità")
        #expect(pace("Groceries").displayName == "Spesa")
        // Legacy rows store the emoji-prefixed shape.
        #expect(pace("🛒 Groceries").displayName == "Spesa")
    }
}
