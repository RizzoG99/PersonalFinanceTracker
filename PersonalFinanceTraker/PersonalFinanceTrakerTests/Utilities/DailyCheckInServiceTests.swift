//
//  DailyCheckInServiceTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

struct DailyCheckInServiceTests {
    private let calendar = Calendar(identifier: .gregorian)

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 12))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    @Test func isPendingWithoutTransactionOrNoSpendConfirmation() {
        let status = DailyCheckInService.computeStatus(
            transactions: [], noSpendDateKeys: [], now: now, calendar: calendar
        )

        #expect(status.state == .pending)
        #expect(!status.isComplete)
        #expect(status.currentStreakDays == 0)
    }

    @Test func noSpendConfirmationCompletesTodayAndExtendsStreak() {
        let status = DailyCheckInService.computeStatus(
            transactions: [TransactionSnapshot.test(timestamp: day(-1), amount: -5, category: "Food")],
            noSpendDateKeys: [DailyCheckInService.dateKey(for: now, calendar: calendar)],
            now: now,
            calendar: calendar
        )

        #expect(status.state == .noSpendConfirmed)
        #expect(status.isComplete)
        #expect(status.currentStreakDays == 2)
    }

    @Test func transactionTakesPrecedenceOverNoSpendConfirmation() {
        let status = DailyCheckInService.computeStatus(
            transactions: [TransactionSnapshot.test(timestamp: now, amount: -5, category: "Food")],
            noSpendDateKeys: [DailyCheckInService.dateKey(for: now, calendar: calendar)],
            now: now,
            calendar: calendar
        )

        #expect(status.state == .transactionLogged)
        #expect(status.currentStreakDays == 1)
    }

    @Test func streakStopsAtFirstUncheckedDay() {
        let status = DailyCheckInService.computeStatus(
            transactions: [TransactionSnapshot.test(timestamp: day(-2), amount: -5, category: "Food")],
            noSpendDateKeys: [
                DailyCheckInService.dateKey(for: now, calendar: calendar),
            ],
            now: now,
            calendar: calendar
        )

        #expect(status.currentStreakDays == 1)
    }

    @Test func dateKeyUsesTheProvidedCalendar() {
        let key = DailyCheckInService.dateKey(for: now, calendar: calendar)
        #expect(key == "2026-08-15")
    }
}
