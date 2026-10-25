import Testing
@testable import PersonalFinanceTraker

/// One-time refresh of installed default categories to the #249 table.
struct DefaultCategoryRefreshTests {

    private func legacy(_ name: String, _ icon: String, _ color: String, _ type: TransactionType = .expense) -> CategoryModel {
        CategoryModel(name: name, systemImage: icon, type: type, colorToken: color)
    }

    @Test func untouchedLegacyDefaultGetsNewIconAndColor() {
        let gas = legacy("Gas", "fuelpump", "categoryIndigo")
        let groceries = legacy("Groceries", "cart", "categoryGreen")
        DefaultCategoryRefresh.apply(to: [gas, groceries])
        #expect(gas.systemImage == "fuelpump.fill")
        #expect(gas.colorToken == "categoryRed")
        #expect(groceries.systemImage == "cart.fill")
        #expect(groceries.colorToken == "categoryOrange")
    }

    @Test func userChosenColorIsKeptButIconStillUpdates() {
        let gas = legacy("Gas", "fuelpump", "categoryPink")
        DefaultCategoryRefresh.apply(to: [gas])
        #expect(gas.colorToken == "categoryPink")
        #expect(gas.systemImage == "fuelpump.fill")
    }

    @Test func userChosenIconIsKept() {
        let gas = legacy("Gas", "motorcycle.fill", "categoryIndigo")
        DefaultCategoryRefresh.apply(to: [gas])
        #expect(gas.systemImage == "motorcycle.fill")
        #expect(gas.colorToken == "categoryRed")
    }

    @Test func customOrRenamedCategoriesAreUntouched() {
        let custom = legacy("Boat", "fuelpump", "categoryIndigo")
        DefaultCategoryRefresh.apply(to: [custom])
        #expect(custom.systemImage == "fuelpump")
        #expect(custom.colorToken == "categoryIndigo")
    }

    @Test func incomeAndExpenseWithTheSameNameUseTheirOwnTable() {
        let income = legacy("Other", "ellipsis.circle", "categoryGray", .income)
        DefaultCategoryRefresh.apply(to: [income])
        #expect(income.systemImage == "ellipsis.circle.fill")
        let salary = legacy("Salary", "banknote", "categoryGreen", .income)
        DefaultCategoryRefresh.apply(to: [salary])
        #expect(salary.colorToken == "categoryGreen")
        let gift = legacy("Gift", "gift", "categoryGreen", .income)
        DefaultCategoryRefresh.apply(to: [gift])
        #expect(gift.colorToken == "categoryPink")
    }

    @Test func applyingTwiceChangesNothingMore() {
        let gas = legacy("Gas", "fuelpump", "categoryIndigo")
        DefaultCategoryRefresh.apply(to: [gas])
        let once = (gas.systemImage, gas.colorToken)
        DefaultCategoryRefresh.apply(to: [gas])
        #expect(gas.systemImage == once.0 && gas.colorToken == once.1)
    }
}
