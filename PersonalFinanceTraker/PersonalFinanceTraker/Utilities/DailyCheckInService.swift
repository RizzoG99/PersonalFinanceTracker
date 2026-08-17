//
//  DailyCheckInService.swift
//  PersonalFinanceTraker
//

import Foundation

enum DailyCheckInState: String, Codable, Equatable, Sendable {
    case pending
    case transactionLogged
    case noSpendConfirmed

    var isComplete: Bool {
        self != .pending
    }
}

struct DailyCheckInStatus: Equatable, Sendable {
    let state: DailyCheckInState
    let currentStreakDays: Int

    var isComplete: Bool {
        state.isComplete
    }
}

enum DailyCheckInService {
    static func computeStatus(
        transactions: [TransactionSnapshot],
        noSpendDateKeys: Set<String>,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DailyCheckInStatus {
        let transactionDateKeys = Set(transactions.map { dateKey(for: $0.timestamp, calendar: calendar) })
        let checkedInDateKeys = transactionDateKeys.union(noSpendDateKeys)
        let todayKey = dateKey(for: now, calendar: calendar)

        let state: DailyCheckInState
        if transactionDateKeys.contains(todayKey) {
            state = .transactionLogged
        } else if noSpendDateKeys.contains(todayKey) {
            state = .noSpendConfirmed
        } else {
            state = .pending
        }

        var currentStreakDays = 0
        var day = calendar.startOfDay(for: now)
        while checkedInDateKeys.contains(dateKey(for: day, calendar: calendar)) {
            currentStreakDays += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previousDay
        }

        return DailyCheckInStatus(state: state, currentStreakDays: currentStreakDays)
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum DailyCheckInStore {
    private static let noSpendDateKeysKey = "financialPulseNoSpendDateKeys"

    static func noSpendDateKeys() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: noSpendDateKeysKey) ?? [])
    }

    static func confirmNoSpend(for date: Date = .now, calendar: Calendar = .current) {
        var keys = noSpendDateKeys()
        keys.insert(DailyCheckInService.dateKey(for: date, calendar: calendar))
        UserDefaults.standard.set(Array(keys).sorted(), forKey: noSpendDateKeysKey)
    }

    static func undoNoSpend(for date: Date = .now, calendar: Calendar = .current) {
        var keys = noSpendDateKeys()
        keys.remove(DailyCheckInService.dateKey(for: date, calendar: calendar))
        UserDefaults.standard.set(Array(keys).sorted(), forKey: noSpendDateKeysKey)
    }
}
