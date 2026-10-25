import Testing
@testable import PersonalFinanceTraker

/// Guards the explicit default-category table and the icon → color suggestion (#249).
struct DefaultCategoryTests {

    private let all = TransactionCategory.defaultCategories

    @Test func thereAreThirtyEightDefaults() {
        #expect(all.count == 38)
    }

    @Test func everyDefaultIconIsInThePickerCatalog() {
        let missing = all.map(\.systemImage).filter { !CategoryConstants.symbolNames.contains($0) }
        #expect(missing.isEmpty, "Not re-selectable in the picker: \(missing)")
    }

    @Test func everyDefaultColorIsInThePickerCatalog() {
        let missing = all.map(\.colorToken).filter { !CategoryConstants.colorTokenNames.contains($0) }
        #expect(missing.isEmpty, "Not in the color picker: \(missing)")
    }

    @Test func noExpenseDefaultIsGreen() {
        let green = TransactionCategory.expenseCategories.filter { $0.colorToken == "categoryGreen" }
        #expect(green.isEmpty, "Expense reads as income: \(green.map(\.label))")
    }

    @Test func colorsNeverRepeatWithinAFamily() {
        for family in TransactionCategory.expenseFamilies {
            let tokens = family.map(\.colorToken)
            #expect(Set(tokens).count == tokens.count, "Shared color in \(family.map(\.label))")
        }
        let income = TransactionCategory.incomeCategories.map(\.colorToken)
        #expect(Set(income).count == income.count)
    }

    @Test func seededModelsUseTheTableNotNameGuessing() {
        let seeded = SampleData.createSampleCategories()
        let groceries = seeded.first { $0.name == "Groceries" }
        #expect(groceries?.colorToken == "categoryOrange")
        #expect(groceries?.systemImage == "cart.fill")
    }

    @Test func everyCatalogSymbolSuggestsANonGreenColor() {
        for symbol in CategoryConstants.symbolNames {
            let token = CategoryConstants.suggestedColorToken(forSymbol: symbol)
            #expect(token != nil, "\(symbol) has no suggestion")
            #expect(token != "categoryGreen", "\(symbol) suggests the income color")
            #expect(token.map(CategoryConstants.colorTokenNames.contains) ?? true)
        }
    }

    @Test func everyIconGroupHasASuggestedColor() {
        // Each group's own first icon resolves, so a new group can't silently suggest nothing.
        for group in CategoryConstants.symbolGroups {
            let first = group.symbols[0]
            #expect(CategoryConstants.suggestedColorToken(forSymbol: first) != nil, "\(group.titleKey)")
        }
    }

    @Test func symbolOutsideTheCatalogSuggestsNothing() {
        #expect(CategoryConstants.suggestedColorToken(forSymbol: "globe") == nil)
    }
}
