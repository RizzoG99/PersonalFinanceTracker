//
//  PendingHabitTemplateStore.swift
//  PersonalFinanceTraker
//

import Foundation

/// A prefilled, unsaved transaction shown for confirmation in the normal add form.
/// It intentionally contains only form fields, never a persisted transaction input.
struct TransactionDraft: Sendable, Equatable {
    let amount: Double
    let transactionType: TransactionType
    let categoryName: String
    let note: String
    let currencyCode: String
    let date: Date

    init(
        amount: Double,
        transactionType: TransactionType,
        categoryName: String,
        note: String,
        currencyCode: String = "EUR",
        date: Date = .now
    ) {
        self.amount = amount
        self.transactionType = transactionType
        self.categoryName = categoryName
        self.note = note
        self.currencyCode = currencyCode
        self.date = date
    }
}

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

    var transactionDraft: TransactionDraft {
        TransactionDraft(
            amount: amount,
            transactionType: isExpense ? .expense : .income,
            categoryName: category,
            note: note
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
