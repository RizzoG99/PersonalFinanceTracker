//
//  DismissedRecurrencePatterns.swift
//  PersonalFinanceTraker
//

import Foundation

/// Suggestions the user answered "Not fixed" to (#188), so detection never offers them again.
/// UserDefaults like `ReceiptCategoryMap`: a short list of user choices, not ledger data.
/// ponytail: not in backups — a restore may re-offer a few; move to SwiftData if that annoys.
enum DismissedRecurrencePatterns {
    private static let defaultsKey = "dismissedRecurrencePatterns"

    static var all: [DismissedRecurrencePattern] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([DismissedRecurrencePattern].self, from: data)) ?? []
    }

    static func dismiss(_ suggestions: [RecurrenceSuggestion]) {
        guard !suggestions.isEmpty else { return }
        let patterns = all + suggestions.map(RecurrenceDetector.dismissalPattern(for:))
        UserDefaults.standard.set(try? JSONEncoder().encode(patterns), forKey: defaultsKey)
    }

    static func removeAll() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
