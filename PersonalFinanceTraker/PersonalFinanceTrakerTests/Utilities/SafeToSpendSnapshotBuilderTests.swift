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

    @Test func sameDayRecurringWithNonMidnightTimeDoesNotDoubleCount() {
        // Test for the double-counting bug: a rule with startDate at non-midnight time
        // (e.g., 14:00) on today should not be counted again in day-1's committed amount
        // if it's already materialized in netSoFar.

        // Create a "now" time that's after 14:00 today, so the rule has already occurred
        var nowComps = calendar.dateComponents([.year, .month, .day], from: Date.now)
        nowComps.hour = 16  // 4 PM
        nowComps.minute = 0
        nowComps.second = 0
        let now = calendar.date(from: nowComps)!

        // Rule starts at 14:00 today (2 hours before "now")
        var startDateComps = calendar.dateComponents([.year, .month, .day], from: now)
        startDateComps.hour = 14  // 2 PM
        startDateComps.minute = 0
        startDateComps.second = 0
        let ruleStartDate = calendar.date(from: startDateComps)!

        // Create a monthly rule starting at 14:00 today
        let rule = RecurrenceRuleSnapshot.test(
            frequency: .monthly,
            interval: 1,
            startDate: ruleStartDate,
            lastMaterializedDate: ruleStartDate,  // Already materialized at the occurrence time
            amount: -100,
            category: "Subscription"
        )

        // Create a transaction that represents the already-materialized occurrence
        let transaction = TransactionSnapshot.test(
            timestamp: ruleStartDate,
            amount: -100,
            category: "Subscription"
        )

        let snapshot = SafeToSpendSnapshotBuilder.build(
            transactions: [transaction],
            activeRules: [rule],
            payCycleStartDay: 1,
            currencyService: currencyService,
            now: now,
            calendar: calendar
        )

        // Day 0 should include the already-materialized transaction
        #expect(snapshot.days[0].amount == -100)

        // Day 1 should NOT double-count the same occurrence (committed should be 0)
        // If the bug existed, day-1 would show -200 (netSoFar + committed from same occurrence)
        #expect(snapshot.days[1].amount == -100, "Day 1 should not double-count today's occurrence")
    }
}
