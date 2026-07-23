//
//  AddTransactionIntent.swift
//  PersonalFinanceTraker
//

import AppIntents
import Foundation

enum QuickAddType: String, AppEnum {
    case expense, income

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Type"
    static let caseDisplayRepresentations: [QuickAddType: DisplayRepresentation] = [
        .expense: "Expense",
        .income: "Income",
    ]
}

struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryEntityQuery()

    let id: String  // category name

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct CategoryEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
        identifiers.map { CategoryEntity(id: $0) }
    }

    func suggestedEntities() async throws -> [CategoryEntity] {
        let repo = TransactionActor.make(AppContainer.shared)
        return try await repo.fetchCategories().map { CategoryEntity(id: $0.name) }
    }
}

struct AddTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Transaction"
    static let description = IntentDescription(
        "Quickly log an expense or income without opening the app."
    )

    @Parameter(title: "Amount", requestValueDialog: "How much?")
    var amount: Double

    @Parameter(title: "Category", requestValueDialog: "Which category?")
    var category: CategoryEntity

    @Parameter(title: "Type", requestValueDialog: "Is this an expense or income?")
    var type: QuickAddType

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$type) of \(\.$amount) in \(\.$category)") {
            \.$note
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repo = TransactionActor.make(AppContainer.shared)
        let categories = try await repo.fetchCategories()
        let input = try QuickAddService.makeInput(
            amount: amount,
            categoryName: category.id,
            isExpense: type == .expense,
            note: note ?? "",
            categories: categories
        )
        try await repo.add(input)
        let formatted = abs(input.amount).formatted(.currency(code: "EUR"))
        return .result(dialog: "Added \(formatted) to \(input.category).")
    }
}

struct PFTShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTransactionIntent(),
            phrases: [
                "Add a transaction in \(.applicationName)",
                "Log an expense in \(.applicationName)",
            ],
            shortTitle: "Add Transaction",
            systemImageName: "plus.circle.fill"
        )
    }
}
