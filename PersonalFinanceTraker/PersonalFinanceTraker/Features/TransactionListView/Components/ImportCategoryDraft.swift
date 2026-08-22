//
//  ImportCategoryDraft.swift
//  PersonalFinanceTraker
//

import Foundation

/// The not-yet-persisted configuration for a category the CSV import will create on confirmation.
struct ImportCategoryDraft: Identifiable, Equatable, Sendable {
    let csvCategory: String
    var name: String
    var type: TransactionType
    var systemImage: String
    var colorToken: String

    var id: String { csvCategory }

    init(
        csvCategory: String,
        name: String,
        type: TransactionType,
        systemImage: String,
        colorToken: String
    ) {
        self.csvCategory = csvCategory
        self.name = name
        self.type = type
        self.systemImage = systemImage
        self.colorToken = colorToken
    }

    init(csvCategory: String, inferredType: TransactionType?) {
        self.csvCategory = csvCategory
        let strippedName = csvCategory.removingLeadingEmoji.trimmingCharacters(in: .whitespaces)
        self.name = strippedName.isEmpty ? csvCategory : strippedName
        self.type = inferredType ?? .expense
        self.systemImage = "tag"
        self.colorToken = "categoryIndigo"
    }
}
