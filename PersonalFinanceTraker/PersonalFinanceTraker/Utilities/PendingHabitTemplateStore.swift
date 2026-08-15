//
//  PendingHabitTemplateStore.swift
//  PersonalFinanceTraker
//

import Foundation

struct PendingHabitTemplateRequest: Codable, Sendable {
    let amount: Double
    let isExpense: Bool
    let category: String
    let note: String
    let createdAt: Date
}

enum PendingHabitTemplateStore {
    private static let key = "pendingHabitTemplateRequest"

    static func save(_ request: PendingHabitTemplateRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        defaults.set(data, forKey: key)
    }

    static func consume() -> PendingHabitTemplateRequest? {
        guard let data = defaults.data(forKey: key),
              let request = try? JSONDecoder().decode(PendingHabitTemplateRequest.self, from: data)
        else { return nil }
        defaults.removeObject(forKey: key)
        return request
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: HabitWidgetSnapshotStore.appGroupIdentifier) ?? .standard
    }
}
