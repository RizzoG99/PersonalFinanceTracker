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

    private func daysAgo(_ n: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: -n, to: now)!
    }

    @Test func todaysAmountIsNetOfThisPayCycleWithNoRecurringRules() {
        let now = Date.now
        let transactions = [
            TransactionSnapshot.test(timestamp: now, amount: 2000, category: "Salary"),
            TransactionSnapshot.test(timestamp: daysAgo(1, from: now), amount: -300, category: "Rent")
        ]
        let snapshot = SafeToSpendSnapshotBuilder.build(
            transactions: transactions,
            activeRules: [],
            payCycleStartDay: 1,
            currencyService: currencyService,
            now: now,
            calendar: calendar
        )
        #expect(snapshot.days.count == 7)
        #expect(snapshot.days[0].amount == 1700)
    }

    @Test func futureRecurringExpenseReducesLaterDaysNotToday() {
        let now = Date.now
        let inThreeDays = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now))!
        let rule = RecurrenceRuleSnapshot.test(
            frequency: .monthly,
            interval: 1,
            startDate: inThreeDays,
            lastMaterializedDate: daysAgo(30, from: now),
            amount: -50,
            category: "Subscription"
        )
        let transactions = [TransactionSnapshot.test(timestamp: now, amount: 500, category: "Salary")]
        let snapshot = SafeToSpendSnapshotBuilder.build(
            transactions: transactions,
            activeRules: [rule],
            payCycleStartDay: 1,
            currencyService: currencyService,
            now: now,
            calendar: calendar
        )
        #expect(snapshot.days[0].amount == 500)       // today: rule hasn't hit yet
        #expect(snapshot.days[2].amount == 500)        // day before the occurrence: still untouched
        #expect(snapshot.days[3].amount == 450)        // occurrence day: committed expense applied
        #expect(snapshot.days[6].amount == 450)        // stays applied through the rest of the window
    }

    @Test func producesExactlySevenDaysStartingToday() {
        let now = Date.now
        let snapshot = SafeToSpendSnapshotBuilder.build(
            transactions: [],
            activeRules: [],
            payCycleStartDay: 1,
            currencyService: currencyService,
            now: now,
            calendar: calendar
        )
        #expect(snapshot.days.count == 7)
        #expect(calendar.isDate(snapshot.days[0].date, inSameDayAs: now))
        let expectedLastDay = calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: now))!
        #expect(calendar.isDate(snapshot.days[6].date, inSameDayAs: expectedLastDay))
    }
}
