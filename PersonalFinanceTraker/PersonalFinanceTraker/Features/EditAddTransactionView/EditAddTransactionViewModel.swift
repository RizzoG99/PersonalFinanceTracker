//
//  EditAddTransactionViewModel.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import Foundation

@Observable @MainActor
final class EditAddTransactionViewModel {
    var transactionName: String = ""
    var amount: Double = 0.0
    var transactionType: TransactionType = .expense
    var currencyCode: String = "EUR"
    var date: Date = Date.now
    var selectedCategory: CategorySnapshot?
    var availableCategories: [CategorySnapshot] = []
    var availableGoals: [GoalSnapshot] = []
    var selectedGoal: GoalSnapshot?
    var showingDatePicker: Bool = false
    var showingCategoryPicker: Bool = false
    var showingErrorAlert: Bool = false
    var errorMessage: String = ""

    let editingItem: TransactionSnapshot?
    private var repo: (any ITransactionRepository)?

    init(transaction: TransactionSnapshot) {
        self.editingItem = transaction
        let type: TransactionType = transaction.goalId != nil ? .transfer
            : transaction.amount < 0 ? .expense : .income
        self.transactionName = transaction.note
        self.amount = abs(Double(truncating: transaction.amount as NSDecimalNumber))
        self.transactionType = type
        self.currencyCode = transaction.currencyCode
        self.date = transaction.timestamp
    }

    init() {
        self.editingItem = nil
    }

    func setRepository(_ repo: any ITransactionRepository) {
        self.repo = repo
        Task {
            do {
                self.availableCategories = try await repo.fetchCategories()
                self.availableGoals = try await repo.fetchGoals()

                // If editing and selectedCategory is nil, try to find it by name for migration
                if let editingItem = editingItem, self.selectedCategory == nil, editingItem.goalId == nil {
                    self.selectedCategory = availableCategories.first(where: { editingItem.category.contains($0.name) })
                }

                // Pre-select goal when editing a transfer
                if let editingItem = editingItem, let goalId = editingItem.goalId {
                    self.selectedGoal = availableGoals.first(where: { $0.id == goalId })
                }

                if editingItem == nil {
                    self.currencyCode = UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func setupForEditing(_ transaction: TransactionSnapshot) {
        // This method can be used if we need to set up editing after the view model is created
        // Currently the setup is done in the init, but this provides flexibility
    }

    var isFormValid: Bool {
        !transactionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        amount > 0 &&
        date <= Date.now &&
        (transactionType == .transfer ? selectedGoal != nil : selectedCategory != nil)
    }

    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return Self.mediumDateFormatter.string(from: date)
    }

    var filteredCategories: [CategorySnapshot] {
        availableCategories.filter { $0.transactionType == transactionType }
    }

    func getTransactionData() -> TransactionInput? {
        if transactionType == .transfer {
            guard let goal = selectedGoal else { return nil }
            let input = TransactionInput(
                timestamp: date,
                amount: -Decimal(amount),
                note: transactionName,
                category: "→ \(goal.name)",
                currencyCode: currencyCode
            )
            resetForm()
            return input
        }

        guard let selectedCategory = selectedCategory else { return nil }
        let finalAmount = transactionType == .income ? Decimal(amount) : -Decimal(amount)
        let input = TransactionInput(
            timestamp: date,
            amount: finalAmount,
            note: transactionName,
            category: selectedCategory.name,
            currencyCode: currencyCode
        )
        resetForm()
        return input
    }

    func getUpdateInput() -> TransactionInput? {
        guard let item = editingItem else { return nil }

        if transactionType == .transfer {
            guard let goal = selectedGoal else { return nil }
            let input = TransactionInput(
                timestamp: date,
                amount: -Decimal(amount),
                note: transactionName,
                category: "→ \(goal.name)",
                currencyCode: currencyCode
            )
            return input
        }

        guard let selectedCategory = selectedCategory else { return nil }
        let finalAmount = transactionType == .income ? Decimal(amount) : -Decimal(amount)
        let input = TransactionInput(
            timestamp: date,
            amount: finalAmount,
            note: transactionName,
            category: selectedCategory.name,
            currencyCode: currencyCode
        )
        return input
    }

    func resetForm() {
        transactionName = ""
        amount = 0.0
        transactionType = .expense
        currencyCode = UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
        date = Date()
        selectedCategory = nil
        selectedGoal = nil
    }

}
