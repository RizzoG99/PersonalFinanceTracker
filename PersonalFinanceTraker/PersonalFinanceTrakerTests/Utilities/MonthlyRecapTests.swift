//
//  MonthlyRecapTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

@MainActor
struct MonthlyRecapTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()
    private let currency = CurrencyService()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Fixed "today": Oct 10, 2026. Cycle start day 1 → closed cycle = September, previous = August.
    private var now: Date { date(2026, 10, 10) }

    private func tx(_ amount: Decimal, _ category: String = "Groceries", on day: Date, note: String = "", goalId: UUID? = nil) -> TransactionSnapshot {
        TransactionSnapshot.test(timestamp: day, amount: amount, note: note, category: category, goalId: goalId)
    }

    private func recap(_ transactions: [TransactionSnapshot], rules: [RecurrenceRuleSnapshot] = [], startDay: Int = 1) -> MonthlyRecap? {
        MonthlyRecap.make(transactions: transactions, rules: rules, payCycleStartDay: startDay,
                          currencyService: currency, now: now, calendar: calendar)
    }

    /// August and September with salary and the given spending; August starts on its first day.
    private func twoCycles(august: Decimal, september: Decimal, augustCategory: String = "Groceries",
                           septemberCategory: String = "Groceries") -> [TransactionSnapshot] {
        [tx(2000, "Salary", on: date(2026, 8, 1, hour: 9)), tx(-august, augustCategory, on: date(2026, 8, 10)),
         tx(2000, "Salary", on: date(2026, 9, 1, hour: 9)), tx(-september, septemberCategory, on: date(2026, 9, 10))]
    }

    @Test func nilWhenClosedCycleIsEmpty() {
        #expect(recap([tx(-50, on: date(2026, 10, 2))]) == nil)
    }

    @Test func closedCycleIsEndExclusive() throws {
        // Oct 1 00:00 belongs to the running cycle, Sep 30 23:00 to the closed one.
        let result = try #require(recap([
            tx(-100, on: date(2026, 9, 30, hour: 23)),
            tx(-999, on: calendar.startOfDay(for: date(2026, 10, 1))),
        ]))
        #expect(result.spent == 100)
        #expect(result.cycleStart == calendar.startOfDay(for: date(2026, 9, 1)))
        #expect(result.cycleEnd == calendar.startOfDay(for: date(2026, 10, 1)))
    }

    @Test func customStartDayUsesPayCycles() throws {
        // Start day 27 → closed cycle Aug 27 – Sep 26, named by its midpoint: September.
        let result = try #require(recap([tx(-80, on: date(2026, 9, 2))], startDay: 27))
        #expect(result.cycleStart == calendar.startOfDay(for: date(2026, 8, 27)))
        #expect(result.name == date(2026, 9, 10).formatted(.dateTime.month(.wide)))
    }

    @Test func goalTransfersCountAsSaved() throws {
        let result = try #require(recap([
            tx(2000, "Salary", on: date(2026, 9, 1, hour: 9)),
            tx(-500, on: date(2026, 9, 5)),
            tx(-300, "→ Japan", on: date(2026, 9, 6), goalId: UUID()),
        ]))
        #expect(result.spent == 500)
        #expect(result.saved == 1500)
    }

    @Test func firstCycleGetsTotalsOnly() throws {
        let result = try #require(recap([tx(2000, "Salary", on: date(2026, 9, 1)), tx(-400, on: date(2026, 9, 3))]))
        #expect(!result.hasComparison)
        #expect(result.savingsRate == 0.8)
    }

    @Test func partialEarlierCycleIsNotCompared() throws {
        // Recording started Aug 20: August is partial, so "€900 more than August" would be noise.
        let result = try #require(recap([tx(-100, on: date(2026, 8, 20)), tx(-1000, on: date(2026, 9, 5))]))
        #expect(!result.hasComparison)
    }

    @Test func spendingDifferenceAndThreshold() throws {
        let less = try #require(recap(twoCycles(august: 1000, september: 853)))
        #expect(less.lines.first == .spending(difference: -147, previousName: date(2026, 8, 10).formatted(.dateTime.month(.wide))))

        // €20 on €1,000 is under 3 %: "about the same".
        let same = try #require(recap(twoCycles(august: 1000, september: 1020)))
        guard case .spending(nil, _) = same.lines.first else { Issue.record("expected about the same"); return }
    }

    @Test func savingsRateLineOnlyWhenItMoves() throws {
        let moved = try #require(recap(twoCycles(august: 1660, september: 1520)))
        let rate = moved.lines.compactMap { if case let .savingsRate(from, to) = $0 { (from, to) } else { nil } }.first
        #expect(abs((rate?.0 ?? 0) - 0.17) < 0.0001 && abs((rate?.1 ?? 0) - 0.24) < 0.0001)

        let flat = try #require(recap(twoCycles(august: 1000, september: 1004)))
        #expect(!flat.lines.contains { if case .savingsRate = $0 { true } else { false } })
    }

    @Test func mostImprovedCountsACategoryCutToZero() throws {
        let transactions = twoCycles(august: 500, september: 500)
            + [tx(-120, "Restaurants", on: date(2026, 8, 15))]
        let result = try #require(recap(transactions))
        #expect(result.lines.contains(.mostImproved(category: "Restaurants", saved: 120)))
    }

    @Test func recurringReflectsAddedAndStoppedRules() throws {
        let rules = [
            // Netflix started in September; the gym stopped mid-September.
            RecurrenceRuleSnapshot.test(startDate: date(2026, 9, 8), amount: -13, note: "Netflix", category: "Subscriptions"),
            RecurrenceRuleSnapshot.test(startDate: date(2026, 1, 3), endDate: date(2026, 9, 15), amount: -35, note: "Gym", category: "Sport"),
        ]
        let result = try #require(recap(twoCycles(august: 500, september: 500), rules: rules))
        #expect(result.lines.contains(.recurring(change: -22)))
    }

    @Test func confirmedRuleWithOlderPaymentsIsNotNew() throws {
        // Spotify confirmed in September (rule starts at its last payment) but paid since July.
        let payments = [7, 8, 9].map { tx(-11, "Subscriptions", on: date(2026, $0, 5), note: "Spotify") }
        let rules = [RecurrenceRuleSnapshot.test(startDate: date(2026, 9, 5), amount: -11, note: "Spotify", category: "Subscriptions")]
        let result = try #require(recap(twoCycles(august: 500, september: 500) + payments, rules: rules))
        #expect(!result.lines.contains { if case .recurring = $0 { true } else { false } })
    }

    @Test func snapshotIsActiveMirrorsTheModel() {
        let stopped = RecurrenceRuleSnapshot.test(startDate: date(2026, 1, 1), endDate: date(2026, 9, 15), amount: -10, category: "X")
        #expect(stopped.isActive(asOf: date(2026, 9, 14)))
        #expect(!stopped.isActive(asOf: date(2026, 9, 16)))
        #expect(RecurrenceRuleSnapshot.test(startDate: date(2026, 1, 1), amount: -10, category: "X").isActive(asOf: now))
    }
}
