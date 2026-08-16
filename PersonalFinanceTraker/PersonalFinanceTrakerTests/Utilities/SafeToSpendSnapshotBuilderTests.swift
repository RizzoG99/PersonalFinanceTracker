//
//  SafeToSpendSnapshotBuilderTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

@Suite("SafeToSpendSnapshotBuilder")
struct SafeToSpendSnapshotBuilderTests {
    private let calendar = Calendar.current
    private let currencyService = CurrencyService(defaults: UserDefaults(suiteName: "SafeToSpendSnapshotBuilderTests")!)

    private func daysAgo(_ days: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)!
    }

    @Test func todaysAmountIsNetOfThisPayCycleWithNoRecurringRules() {
        let now = Date.now
        let snapshot = SafeToSpendSnapshotBuilder.build(
            transactions: [
                TransactionSnapshot.test(timestamp: now, amount: 2_000, category: "Salary"),
                TransactionSnapshot.test(timestamp: daysAgo(1, from: now), amount: -300, category: "Rent")
            ],
            activeRules: [],
            payCycleStartDay: 1,
            currencyService: currencyService,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.days.count == 7)
        #expect(snapshot.days[0].amount == 1_700)
    }

    @Test func futureRecurringExpenseReducesLaterDaysNotToday() {
        let now = Date.now
        let dueDate = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now))!
        let rule = RecurrenceRuleSnapshot.test(
            frequency: .monthly,
            interval: 1,
            startDate: dueDate,
            lastMaterializedDate: daysAgo(30, from: now),
            amount: -50,
            category: "Subscription"
        )
        let snapshot = SafeToSpendSnapshotBuilder.build(
            transactions: [TransactionSnapshot.test(timestamp: now, amount: 500, category: "Salary")],
            activeRules: [rule],
            payCycleStartDay: 1,
            currencyService: currencyService,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.days[0].amount == 500)
        #expect(snapshot.days[2].amount == 500)
        #expect(snapshot.days[3].amount == 450)
        #expect(snapshot.days[6].amount == 450)
    }

    @Test func materializedSameDayRecurrenceIsNotDoubleCounted() {
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = 16
        let now = calendar.date(from: components)!

        var occurrenceComponents = calendar.dateComponents([.year, .month, .day], from: now)
        occurrenceComponents.hour = 14
        let occurrence = calendar.date(from: occurrenceComponents)!
        let rule = RecurrenceRuleSnapshot.test(
            frequency: .monthly,
            interval: 1,
            startDate: occurrence,
            lastMaterializedDate: occurrence,
            amount: -100,
            category: "Subscription"
        )

        let snapshot = SafeToSpendSnapshotBuilder.build(
            transactions: [TransactionSnapshot.test(timestamp: occurrence, amount: -100, category: "Subscription")],
            activeRules: [rule],
            payCycleStartDay: 1,
            currencyService: currencyService,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.days[0].amount == -100)
        #expect(snapshot.days[1].amount == -100)
    }

    @Test func forecastEndIsTheSeventhForecastDay() {
        let now = Date.now
        let snapshot = SafeToSpendSnapshotBuilder.build(
            transactions: [],
            activeRules: [],
            payCycleStartDay: 1,
            currencyService: currencyService,
            now: now,
            calendar: calendar
        )
        let expectedEnd = calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: now))!
        #expect(calendar.isDate(snapshot.forecastEnd, inSameDayAs: expectedEnd))
    }
}
