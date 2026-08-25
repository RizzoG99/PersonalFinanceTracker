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
}
