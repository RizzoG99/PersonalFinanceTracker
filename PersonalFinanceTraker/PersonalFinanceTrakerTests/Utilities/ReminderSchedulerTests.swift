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
            now: now, hour: 21, minute: 0, hasCompletedToday: false
        )
        #expect(dates.count == 7)
        let first = Calendar.current.dateComponents([.day, .hour], from: dates[0])
        #expect(first.day == 23)
        #expect(first.hour == 21)
    }

    @Test func skipsTodayWhenAlreadyLogged() {
        let dates = ReminderScheduler.fireDates(
            now: now, hour: 21, minute: 0, hasCompletedToday: true
        )
        #expect(dates.count == 6)
        #expect(Calendar.current.component(.day, from: dates[0]) == 24)
    }

    @Test func skipsTodayWhenTimeHasPassed() {
        let dates = ReminderScheduler.fireDates(
            now: now, hour: 9, minute: 0, hasCompletedToday: false
        )
        #expect(dates.count == 6)
        #expect(Calendar.current.component(.day, from: dates[0]) == 24)
    }

    // The reminder copy is resolved in the device's language, so asserting the English wording
    // directly only held on an English simulator — on an Italian one the same correct code returned
    // "Registra le spese di oggi" and the test failed. Split into the two things actually worth
    // protecting: that the service still points at these catalogue keys, and that both languages
    // have real copy behind them.

    @Test func reminderCopyUsesTheHabitLoopKeys() {
        #expect(ReminderService.reminderTitle == String(localized: "Log today's spending"))
        #expect(ReminderService.reminderBody == String(localized: "Take 30 seconds to keep your streak."))
    }

    @Test func reminderCopyIsTranslatedInEveryShippedLanguage() throws {
        let expected = [
            "en": ("Log today's spending", "Take 30 seconds to keep your streak."),
            "it": ("Registra le spese di oggi", "Ti bastano 30 secondi per mantenere la serie."),
        ]
        for (language, copy) in expected {
            // The language bundle, not String(localized:locale:) — that initializer's locale only
            // affects how interpolations are formatted, not which table is consulted, so it returned
            // the simulator's language for both entries.
            let bundle = try #require(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "no \(language).lproj in the app bundle"
            )
            #expect(bundle.localizedString(forKey: "Log today's spending", value: nil, table: nil) == copy.0)
            #expect(bundle.localizedString(
                forKey: "Take 30 seconds to keep your streak.", value: nil, table: nil) == copy.1)
        }
    }
}
