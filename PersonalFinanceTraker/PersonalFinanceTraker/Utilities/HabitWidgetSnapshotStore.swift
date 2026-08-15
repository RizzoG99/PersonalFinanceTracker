//
//  HabitWidgetSnapshotStore.swift
//  PersonalFinanceTraker
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct HabitWidgetQuickTemplate: Identifiable, Equatable, Sendable, Codable {
    var id: String { [label, category, note, currencyCode, String(isExpense), amount.description].joined(separator: "|") }

    let label: String
    let amount: Double
    let isExpense: Bool
    let category: String
    let note: String
    let currencyCode: String
}

struct HabitWidgetSnapshot: Equatable, Sendable, Codable {
    let hasLoggedToday: Bool
    let todayCount: Int
    let currentStreakDays: Int
    let checkInState: DailyCheckInState?
    let checkInStreakDays: Int?
    let quickTemplates: [HabitWidgetQuickTemplate]
    let lastUpdated: Date

    static let empty = HabitWidgetSnapshot(
        hasLoggedToday: false,
        todayCount: 0,
        currentStreakDays: 0,
        checkInState: .pending,
        checkInStreakDays: 0,
        quickTemplates: [],
        lastUpdated: .distantPast
    )

    var resolvedCheckInState: DailyCheckInState {
        checkInState ?? (hasLoggedToday ? .transactionLogged : .pending)
    }

    var resolvedCheckInStreakDays: Int {
        checkInStreakDays ?? currentStreakDays
    }
}

enum HabitWidgetSnapshotStore {
    static let appGroupIdentifier = "group.rizzoG99.PersonalFinanceTraker"
    private static let key = "dailyLoggingHabitSnapshot"

    static func makeSnapshot(
        status: DailyLoggingStatus,
        checkInStatus: DailyCheckInStatus,
        templates: [QuickTransactionTemplate],
        now: Date = .now
    ) -> HabitWidgetSnapshot {
        HabitWidgetSnapshot(
            hasLoggedToday: status.hasLoggedToday,
            todayCount: status.todayCount,
            currentStreakDays: status.currentStreakDays,
            checkInState: checkInStatus.state,
            checkInStreakDays: checkInStatus.currentStreakDays,
            quickTemplates: templates.map {
                HabitWidgetQuickTemplate(
                    label: $0.displayLabel,
                    amount: $0.amountMagnitudeDouble,
                    isExpense: $0.isExpense,
                    category: $0.category,
                    note: $0.note,
                    currencyCode: $0.currencyCode
                )
            },
            lastUpdated: now
        )
    }

    static func save(_ snapshot: HabitWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "DailyLoggingHabitWidget")
        #endif
    }

    static func load() -> HabitWidgetSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(HabitWidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}
