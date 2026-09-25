import Testing
@testable import PersonalFinanceTraker

/// #150: the category picker in the Add Transaction sheet renders
/// `name.localizedCategoryDisplay` but used to filter on the raw stored `name`, so every
/// built-in category was unsearchable by the name actually shown outside English.
@Suite @MainActor struct CategoryPickerSearchTests {

    private let categories: [CategorySnapshot] = [
        .test(name: "Groceries"),
        .test(name: "Transport"),
    ]

    @Test func matchesTheRawEnglishName() {
        let hits = CategoryPickerSheet.matching(categories, search: "grocer")
        #expect(hits.map(\.name) == ["Groceries"])
    }

    @Test func emptySearchReturnsEverything() {
        #expect(CategoryPickerSheet.matching(categories, search: "").count == 2)
    }

    /// Only observable in a localized run: `scripts/xcb test -testLanguage it`.
    /// In English the catalog is the identity and there is nothing to assert — the condition
    /// trait rather than an early `return` so that case reports as *skipped*, not as passed.
    /// A silent early return is how the first #150 fix shipped looking green.
    @Test(.enabled(if: "Groceries".localizedCategoryDisplay != "Groceries"))
    func matchesTheLocalizedNameTheChipDisplays() {
        let shown = "Groceries".localizedCategoryDisplay
        let hits = CategoryPickerSheet.matching(categories, search: shown.lowercased())
        #expect(hits.map(\.name) == ["Groceries"])
    }
}
