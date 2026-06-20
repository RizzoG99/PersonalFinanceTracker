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
    var selectedCategory: CategoryModel?
    var availableCategories: [CategoryModel] = []
    var availableGoals: [GoalModel] = []
    var selectedGoal: GoalModel?
    var showingDatePicker: Bool = false
    var showingCategoryPicker: Bool = false
    var showingErrorAlert: Bool = false
    var errorMessage: String = ""
    
    let editingItem: TransactionModel?
    private var transactionViewModel: TransactionListViewModel?
    
    init(transaction: TransactionModel) {
        self.editingItem = transaction
        let type: TransactionType = transaction.goalId != nil ? .transfer
            : transaction.amount < 0 ? .expense : .income
        self.transactionName = transaction.note
        self.amount = abs(Double(truncating: transaction.amount as NSDecimalNumber))
        self.transactionType = type
        self.currencyCode = transaction.currencyCode
        self.date = transaction.timestamp
        self.selectedCategory = transaction.categoryModel
    }
    
    init() {
        self.editingItem = nil
    }
    
    func setTransactionViewModel(_ transactionViewModel: TransactionListViewModel) {
        self.transactionViewModel = transactionViewModel
        self.availableCategories = (try? transactionViewModel.repo.fetchCategories()) ?? []
        self.availableGoals = (try? transactionViewModel.repo.fetchGoals()) ?? []

        // If editing and categoryModel is nil, try to find it by name for migration
        if let editingItem = editingItem, editingItem.categoryModel == nil, editingItem.goalId == nil {
            self.selectedCategory = availableCategories.first(where: { editingItem.category.contains($0.name) })
        }

        // Pre-select goal when editing a transfer
        if let editingItem = editingItem, let goalId = editingItem.goalId {
            self.selectedGoal = availableGoals.first(where: { $0.id == goalId })
        }

        if editingItem == nil {
            self.currencyCode = UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
        }
    }
    
    func setupForEditing(_ transaction: TransactionModel) {
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
    
    var filteredCategories: [CategoryModel] {
        availableCategories.filter { $0.transactionType == transactionType }
    }
    
    func getTransactionData() -> TransactionModel? {
        if transactionType == .transfer {
            guard let goal = selectedGoal else { return nil }
            let newItem = TransactionModel(
                timestamp: date,
                amount: -Decimal(amount),
                note: transactionName,
                category: "→ \(goal.name)",
                currencyCode: currencyCode,
                goalId: goal.id
            )
            resetForm()
            return newItem
        }

        guard let selectedCategory = selectedCategory else { return nil }
        let finalAmount = transactionType == .income ? Decimal(amount) : -Decimal(amount)
        let newItem = TransactionModel(
            timestamp: date,
            amount: finalAmount,
            note: transactionName,
            category: selectedCategory.name,
            categoryModel: selectedCategory,
            currencyCode: currencyCode
        )
        resetForm()
        return newItem
    }
    
    func updateTransaction() {
        guard let item = editingItem else { return }

        if transactionType == .transfer {
            guard let goal = selectedGoal else { return }
            item.timestamp = date
            item.amount = -Decimal(amount)
            item.note = transactionName
            item.category = "→ \(goal.name)"
            item.categoryModel = nil
            item.currencyCode = currencyCode
            item.goalId = goal.id
            return
        }

        guard let selectedCategory = selectedCategory else { return }
        let finalAmount = transactionType == .income ? Decimal(amount) : -Decimal(amount)
        item.timestamp = date
        item.amount = finalAmount
        item.note = transactionName
        item.category = selectedCategory.name
        item.categoryModel = selectedCategory
        item.currencyCode = currencyCode
        item.goalId = nil
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
