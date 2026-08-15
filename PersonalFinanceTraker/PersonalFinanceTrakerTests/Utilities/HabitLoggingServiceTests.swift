//
//  HabitLoggingServiceTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

struct HabitLoggingServiceTests {
    private let calendar = Calendar(identifier: .gregorian)

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 12))!
    }

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let date = calendar.date(byAdding: .day, value: offset, to: now)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
    }

    @Test func statusForNoTransactions() {
        let status = HabitLoggingService.computeStatus(transactions: [], now: now, calendar: calendar)
        #expect(!status.hasLoggedToday)
        #expect(status.todayCount == 0)
        #expect(status.currentStreakDays == 0)
    }

    @Test func statusCountsLoggedToday() {
        let transactions = [
            TransactionSnapshot.test(timestamp: day(0, hour: 9), amount: -5, category: "Food"),
        ]
        let status = HabitLoggingService.computeStatus(transactions: transactions, now: now, calendar: calendar)
        #expect(status.hasLoggedToday)
        #expect(status.todayCount == 1)
        #expect(status.currentStreakDays == 1)
    }

    @Test func statusCountsMultipleTransactionsToday() {
        let transactions = [
            TransactionSnapshot.test(timestamp: day(0, hour: 9), amount: -5, category: "Food"),
            TransactionSnapshot.test(timestamp: day(0, hour: 10), amount: -6, category: "Food"),
        ]
        let status = HabitLoggingService.computeStatus(transactions: transactions, now: now, calendar: calendar)
        #expect(status.todayCount == 2)
        #expect(status.currentStreakDays == 1)
    }

    @Test func statusCountsConsecutiveStreak() {
        let transactions = [
            TransactionSnapshot.test(timestamp: day(0), amount: -5, category: "Food"),
            TransactionSnapshot.test(timestamp: day(-1), amount: -6, category: "Food"),
            TransactionSnapshot.test(timestamp: day(-2), amount: 100, category: "Salary"),
        ]
        let status = HabitLoggingService.computeStatus(transactions: transactions, now: now, calendar: calendar)
        #expect(status.currentStreakDays == 3)
    }

    @Test func statusStopsAtBrokenStreak() {
        let transactions = [
            TransactionSnapshot.test(timestamp: day(0), amount: -5, category: "Food"),
            TransactionSnapshot.test(timestamp: day(-2), amount: -6, category: "Food"),
        ]
        let status = HabitLoggingService.computeStatus(transactions: transactions, now: now, calendar: calendar)
        #expect(status.currentStreakDays == 1)
    }

    @Test func quickTemplatesExcludeTransfers() {
        let goalId = UUID()
        let transactions = [
            TransactionSnapshot.test(timestamp: day(-1), amount: -20, note: "Transfer", category: "Savings", goalId: goalId),
            TransactionSnapshot.test(timestamp: day(-2), amount: -8, note: "Coffee", category: "Food"),
        ]
        let templates = HabitLoggingService.quickTemplates(from: transactions, now: now, calendar: calendar)
        #expect(templates.count == 1)
        #expect(templates.first?.note == "Coffee")
    }

    @Test func quickTemplatesDedupeRepeatedTemplates() {
        let transactions = [
            TransactionSnapshot.test(timestamp: day(-1), amount: -8, note: "Coffee", category: "Food"),
            TransactionSnapshot.test(timestamp: day(-2), amount: -8, note: "Coffee", category: "Food"),
            TransactionSnapshot.test(timestamp: day(-3), amount: -12, note: "Lunch", category: "Food"),
        ]
        let templates = HabitLoggingService.quickTemplates(from: transactions, now: now, calendar: calendar)
        #expect(templates.count == 2)
        #expect(templates.first?.frequency == 2)
        #expect(templates.first?.note == "Coffee")
    }

    @Test func quickTemplatesSortByFrequencyThenRecency() {
        let transactions = [
            TransactionSnapshot.test(timestamp: day(-1), amount: -4, note: "Recent", category: "Food"),
            TransactionSnapshot.test(timestamp: day(-2), amount: -8, note: "Frequent", category: "Food"),
            TransactionSnapshot.test(timestamp: day(-3), amount: -8, note: "Frequent", category: "Food"),
            TransactionSnapshot.test(timestamp: day(-4), amount: -3, note: "Older", category: "Food"),
        ]
        let templates = HabitLoggingService.quickTemplates(from: transactions, now: now, calendar: calendar)
        #expect(templates.map(\.note) == ["Frequent", "Recent", "Older"])
    }

    @Test func quickTemplatesPreserveIncomeAndExpenseSigns() {
        let transactions = [
            TransactionSnapshot.test(timestamp: day(-1), amount: 100, note: "Pay", category: "Salary"),
            TransactionSnapshot.test(timestamp: day(-2), amount: -8, note: "Coffee", category: "Food"),
        ]
        let templates = HabitLoggingService.quickTemplates(from: transactions, now: now, calendar: calendar)
        #expect(templates.contains { $0.note == "Pay" && !$0.isExpense && $0.amount == 100 })
        #expect(templates.contains { $0.note == "Coffee" && $0.isExpense && $0.amount == -8 })
    }

    @Test func reminderPromptRequiresEnoughHistoryAndOptInGap() {
        let transactions = [
            TransactionSnapshot.test(timestamp: day(0), amount: -5, category: "Food"),
            TransactionSnapshot.test(timestamp: day(-1), amount: -6, category: "Food"),
            TransactionSnapshot.test(timestamp: day(-2), amount: -7, category: "Food"),
        ]

        #expect(HabitLoggingService.shouldShowReminderPrompt(
            transactions: transactions,
            remindersEnabled: false,
            promptDismissed: false,
            calendar: calendar
        ))
        #expect(!HabitLoggingService.shouldShowReminderPrompt(
            transactions: transactions,
            remindersEnabled: true,
            promptDismissed: false,
            calendar: calendar
        ))
        #expect(!HabitLoggingService.shouldShowReminderPrompt(
            transactions: transactions,
            remindersEnabled: false,
            promptDismissed: true,
            calendar: calendar
        ))
    }
}
