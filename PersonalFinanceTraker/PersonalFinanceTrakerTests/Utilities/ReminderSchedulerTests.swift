//
//  ReminderSchedulerTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

struct ReminderSchedulerTests {

    // Fixed "now": 2026-07-23 10:00 local
    private var now: Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 7, day: 23, hour: 10, minute: 0)
        )!
    }

    @Test func schedulesSevenDaysWhenReminderTimeIsAhead() {
        let dates = ReminderScheduler.fireDates(
            now: now, hour: 21, minute: 0, hasLoggedToday: false
        )
        #expect(dates.count == 7)
        let first = Calendar.current.dateComponents([.day, .hour], from: dates[0])
        #expect(first.day == 23)
        #expect(first.hour == 21)
    }

    @Test func skipsTodayWhenAlreadyLogged() {
        let dates = ReminderScheduler.fireDates(
            now: now, hour: 21, minute: 0, hasLoggedToday: true
        )
        #expect(dates.count == 6)
        #expect(Calendar.current.component(.day, from: dates[0]) == 24)
    }

    @Test func skipsTodayWhenTimeHasPassed() {
        let dates = ReminderScheduler.fireDates(
            now: now, hour: 9, minute: 0, hasLoggedToday: false
        )
        #expect(dates.count == 6)
        #expect(Calendar.current.component(.day, from: dates[0]) == 24)
    }
}
