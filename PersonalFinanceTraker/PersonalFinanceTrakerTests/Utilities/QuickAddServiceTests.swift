//
//  QuickAddServiceTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

struct QuickAddServiceTests {

    @Test func expenseIsStoredNegative() throws {
        let input = try QuickAddService.makeInput(
            amount: 12.5, categoryName: "Food", isExpense: true,
            note: "", categories: []
        )
        #expect(input.amount == Decimal(string: "-12.5"))
    }

    @Test func negativeAmountIsForgivenAsMagnitude() throws {
        let input = try QuickAddService.makeInput(
            amount: -100, categoryName: "Food", isExpense: true,
            note: "", categories: []
        )
        #expect(input.amount == Decimal(-100))
    }

    @Test func incomeIsStoredPositive() throws {
        let input = try QuickAddService.makeInput(
            amount: 100, categoryName: "Salary", isExpense: false,
            note: "", categories: []
        )
        #expect(input.amount == Decimal(100))
    }

    @Test func amountIsRoundedToTwoDecimals() throws {
        let input = try QuickAddService.makeInput(
            amount: 3.499999, categoryName: "Food", isExpense: true,
            note: "", categories: []
        )
        #expect(input.amount == Decimal(string: "-3.5"))
    }

    @Test func knownCategoryResolvesCaseInsensitively() throws {
        let food = CategorySnapshot.test(name: "Food")
        let input = try QuickAddService.makeInput(
            amount: 5, categoryName: "food", isExpense: true,
            note: "", categories: [food]
        )
        #expect(input.category == "Food")
        #expect(input.categoryPersistentId == food.persistentId)
    }

    @Test func unknownCategoryKeepsNameWithoutLink() throws {
        let input = try QuickAddService.makeInput(
            amount: 5, categoryName: "Mystery", isExpense: true,
            note: "", categories: [CategorySnapshot.test(name: "Food")]
        )
        #expect(input.category == "Mystery")
        #expect(input.categoryPersistentId == nil)
    }

    @Test func zeroAmountThrows() {
        #expect(throws: QuickAddError.self) {
            _ = try QuickAddService.makeInput(
                amount: 0, categoryName: "Food", isExpense: true,
                note: "", categories: []
            )
        }
    }
}
