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

    init(amount: Double, isExpense: Bool, category: String, note: String, createdAt: Date) {
        self.amount = amount
        self.isExpense = isExpense
        self.category = category
        self.note = note
        self.createdAt = createdAt
    }

    init?(widgetURL: URL) {
        guard let components = URLComponents(url: widgetURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let amountValue = queryItems.first(where: { $0.name == "amount" })?.value,
              let amount = Double(amountValue),
              let expenseValue = queryItems.first(where: { $0.name == "isExpense" })?.value,
              let isExpense = Bool(expenseValue),
              let category = queryItems.first(where: { $0.name == "category" })?.value,
              let note = queryItems.first(where: { $0.name == "note" })?.value
        else { return nil }

        self.init(
            amount: amount,
            isExpense: isExpense,
            category: category,
            note: note,
            createdAt: .now
        )
    }
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
