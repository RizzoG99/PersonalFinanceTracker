//
//  EditAddTransactionViewModel.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import Foundation

final class EditAddTransactionViewModel: ObservableObject {
    @Published var transactionName: String = ""
    @Published var amount: Double = 0.0 // Changed from Decimal to Double for CurrencyAmountField
    @Published var transactionType: TransactionType = .expense
    @Published var date: Date = Date()
    @Published var selectedCategory: TransactionCategory?
    @Published var showingDatePicker: Bool = false
    @Published var showingCategoryPicker: Bool = false
    @Published var showingErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    
    let editingItem: TransactionModel?
    private var transactionViewModel: TransactionListViewModel?
    
    init(transaction: TransactionModel) {
        self.editingItem = transaction
        let transactionType: TransactionType = transaction.amount < 0 ? .expense : .income
        let categoryType = transactionType == .expense ? TransactionCategory.expenseCategories : TransactionCategory.incomeCategories
        
        self._transactionName = Published(initialValue: transaction.note)
        self._amount = Published(initialValue: abs(Double(truncating: transaction.amount as NSDecimalNumber)))
        self._transactionType = Published(initialValue: transactionType)
        self._date = Published(initialValue: transaction.timestamp)
        self._selectedCategory = Published(initialValue: categoryType.first(where: { transaction.category.contains($0.emoji) }))
    }
    
    init() {
        self.editingItem = nil
    }
    
    func setTransactionViewModel(_ transactionViewModel: TransactionListViewModel) {
        self.transactionViewModel = transactionViewModel
    }
    
    func setupForEditing(_ transaction: TransactionModel) {
        // This method can be used if we need to set up editing after the view model is created
        // Currently the setup is done in the init, but this provides flexibility
    }
    
    var isFormValid: Bool {
        !transactionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        amount > 0 &&
        date <= Date() &&
        selectedCategory != nil
    }
    
    var formattedDate: String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
    
    var filteredCategories: [TransactionCategory] {
        TransactionCategory.defaultCategories.filter { category in
            switch transactionType {
            case .income:
                return TransactionCategory.incomeCategories.contains { $0.id == category.id }
            case .expense:
                return TransactionCategory.expenseCategories.contains { $0.id == category.id }
            }
        }
    }
    
    func getTransactionData() -> TransactionModel? {
        guard let selectedCategory = selectedCategory else { return nil }
        
        // Calculate the final amount based on transaction type
        let finalAmount = transactionType == .income ? Decimal(amount) : -Decimal(amount)
        
        // Create a new transaction item
        let newItem = TransactionModel(
            timestamp: date,
            amount: finalAmount,
            note: transactionName,
            category: selectedCategory.displayText
        )
        
        print("Adding transaction: \(transactionName), Amount: \(finalAmount), Date: \(date), Category: \(selectedCategory.displayText), Type: \(transactionType.rawValue)")
        
        resetForm()
        return newItem
    }
    
    func updateTransaction() {
        guard let selectedCategory = selectedCategory,
              let item = editingItem else { return }
        
        // Calculate the final amount based on transaction type
        let finalAmount = transactionType == .income ? Decimal(amount) : -Decimal(amount)
        
        // Update the existing item
        item.timestamp = date
        item.amount = finalAmount
        item.note = transactionName
        item.category = selectedCategory.displayText
        
        print("Updating transaction: \(transactionName), Amount: \(finalAmount), Date: \(date), Category: \(selectedCategory.displayText), Type: \(transactionType.rawValue)")
    }
    
    func resetForm() {
        transactionName = ""
        amount = 0.0
        transactionType = .expense
        date = Date()
        selectedCategory = nil
    }

}
