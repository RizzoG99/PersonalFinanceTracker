//
//  SearchTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

@Suite("SearchFilters.matches")
struct SearchTests {

    private func date(daysAgo: Int, hour: Int = 12) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    @Test func expenseTypeFilterReturnsOnlyNegativeAmounts() {
        let filters = SearchFilters(type: .expense)

        let expense = TransactionSnapshot.test(timestamp: .now, amount: -50, category: "Food")
        let income = TransactionSnapshot.test(timestamp: .now, amount: 2500, category: "Salary")
        let neutral = TransactionSnapshot.test(timestamp: .now, amount: 0, category: "Test")

        #expect(filters.matches(expense) == true)
        #expect(filters.matches(income) == false)
        #expect(filters.matches(neutral) == false)
    }

    @Test func incomeTypeFilterReturnsOnlyPositiveAmounts() {
        let filters = SearchFilters(type: .income)

        let income = TransactionSnapshot.test(timestamp: .now, amount: 2500, category: "Salary")
        let expense = TransactionSnapshot.test(timestamp: .now, amount: -50, category: "Food")
        let neutral = TransactionSnapshot.test(timestamp: .now, amount: 0, category: "Test")

        #expect(filters.matches(income) == true)
        #expect(filters.matches(expense) == false)
        #expect(filters.matches(neutral) == false)
    }

    @Test func categoryFilterMatchesOnlySelectedCategories() {
        var filters = SearchFilters()
        filters.categories = ["Food", "Transport"]

        let food = TransactionSnapshot.test(timestamp: .now, amount: -50, category: "Food")
        let transport = TransactionSnapshot.test(timestamp: .now, amount: -60, category: "Transport")
        let leisure = TransactionSnapshot.test(timestamp: .now, amount: -15, category: "Leisure")

        #expect(filters.matches(food) == true)
        #expect(filters.matches(transport) == true)
        #expect(filters.matches(leisure) == false)
    }

    @Test func customDateRangeIncludesTransactionOnEndDay() {
        let startDate = date(daysAgo: 3)
        let endDate = Calendar.current.startOfDay(for: .now)

        var filters = SearchFilters()
        filters.dateRange = .custom(from: startDate, to: endDate)

        // Transaction at 14:00 on the end day should be included
        let transactionOnEndDay = TransactionSnapshot.test(
            timestamp: date(daysAgo: 0, hour: 14),
            amount: -50,
            category: "Food"
        )

        // Transaction before start date should be excluded
        let transactionBeforeStart = TransactionSnapshot.test(
            timestamp: date(daysAgo: 5),
            amount: -50,
            category: "Food"
        )

        #expect(filters.matches(transactionOnEndDay) == true)
        #expect(filters.matches(transactionBeforeStart) == false)
    }

    @Test func amountBoundsFilterOnAbsoluteValue() {
        var filters = SearchFilters()
        filters.amountMin = 50
        filters.amountMax = 500

        let withinBounds = TransactionSnapshot.test(timestamp: .now, amount: -100, category: "Food")
        let belowMin = TransactionSnapshot.test(timestamp: .now, amount: -30, category: "Food")
        let aboveMax = TransactionSnapshot.test(timestamp: .now, amount: -600, category: "Food")
        let positiveWithinBounds = TransactionSnapshot.test(timestamp: .now, amount: 150, category: "Salary")

        #expect(filters.matches(withinBounds) == true)
        #expect(filters.matches(belowMin) == false)
        #expect(filters.matches(aboveMax) == false)
        #expect(filters.matches(positiveWithinBounds) == true)
    }

    @Test func emptyFiltersMatchEverything() {
        let filters = SearchFilters()

        let expense = TransactionSnapshot.test(timestamp: .now, amount: -50, category: "Food")
        let income = TransactionSnapshot.test(timestamp: .now, amount: 2500, category: "Salary")
        let zero = TransactionSnapshot.test(timestamp: .now, amount: 0, category: "Test")

        #expect(filters.matches(expense) == true)
        #expect(filters.matches(income) == true)
        #expect(filters.matches(zero) == true)
    }
}
