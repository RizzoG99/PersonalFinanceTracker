//
//  PendingHabitAddStore.swift
//  PersonalFinanceTraker
//

import Foundation

enum PendingHabitAddStore {
    private static let key = "pendingHabitAddRequest"

    static func save() {
        defaults.set(true, forKey: key)
    }

    static func consume() -> Bool {
        let pending = defaults.bool(forKey: key)
        if pending {
            defaults.removeObject(forKey: key)
        }
        return pending
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: HabitWidgetSnapshotStore.appGroupIdentifier) ?? .standard
    }
}
