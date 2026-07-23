//
//  QuickAddService.swift
//  PersonalFinanceTraker
//
//  Pure transaction-building logic for the Add Transaction App Intent,
//  separated so it's testable without AppIntents machinery.
//

import Foundation

enum QuickAddError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidAmount: "The amount must be greater than zero."
        }
    }
}

struct QuickAddService {
    static func makeInput(
        amount: Double,
        categoryName: String,
        isExpense: Bool,
        note: String,
        categories: [CategorySnapshot],
        now: Date = .now
    ) throws -> TransactionInput {
        guard amount > 0 else { throw QuickAddError.invalidAmount }
        // Round via string to avoid Double's binary representation noise
        guard let magnitude = Decimal(
            string: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), amount)
        ) else { throw QuickAddError.invalidAmount }

        let signed = isExpense ? -magnitude : magnitude
        let match = categories.first {
            $0.name.caseInsensitiveCompare(categoryName) == .orderedSame
        }
        return TransactionInput(
            timestamp: now,
            amount: signed,
            note: note,
            category: match?.name ?? categoryName,
            currencyCode: "EUR",
            categoryPersistentId: match?.persistentId
        )
    }
}
