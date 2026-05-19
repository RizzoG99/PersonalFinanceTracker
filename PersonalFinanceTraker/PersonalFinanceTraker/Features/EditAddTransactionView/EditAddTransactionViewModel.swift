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
    @Published var currencyCode: String = "EUR"
    @Published var date: Date = Date()
    @Published var selectedCategory: CategoryModel?
    @Published var availableCategories: [CategoryModel] = []
    @Published var showingDatePicker: Bool = false
    @Published var showingCategoryPicker: Bool = false
    @Published var showingErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    
    let editingItem: TransactionModel?
    private var transactionViewModel: TransactionListViewModel?
    
    init(transaction: TransactionModel) {
        self.editingItem = transaction
        let transactionType: TransactionType = transaction.amount < 0 ? .expense : .income
        
        self._transactionName = Published(initialValue: transaction.note)
        self._amount = Published(initialValue: abs(Double(truncating: transaction.amount as NSDecimalNumber)))
        self._transactionType = Published(initialValue: transactionType)
        self._currencyCode = Published(initialValue: transaction.currencyCode)
        self._date = Published(initialValue: transaction.timestamp)
        self._selectedCategory = Published(initialValue: transaction.categoryModel)
    }
    
    init() {
        self.editingItem = nil
    }
    
    func setTransactionViewModel(_ transactionViewModel: TransactionListViewModel) {
        self.transactionViewModel = transactionViewModel
        // Fetch categories when view model is linked
        self.availableCategories = (try? transactionViewModel.repo.fetchCategories()) ?? []
        
        // If editing and categoryModel is nil, try to find it by name for migration
        if let editingItem = editingItem, editingItem.categoryModel == nil {
            self.selectedCategory = availableCategories.first(where: { editingItem.category.contains($0.name) })
        }
        
        // Set default currency from user settings if not editing
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
    
    var filteredCategories: [CategoryModel] {
        availableCategories.filter { $0.transactionType == transactionType }
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
            category: selectedCategory.displayText,
            categoryModel: selectedCategory,
            currencyCode: currencyCode
        )
        
        print("Adding transaction: \(transactionName), Amount: \(finalAmount) \(currencyCode), Date: \(date), Category: \(selectedCategory.displayText), Type: \(transactionType.rawValue)")
        
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
        item.categoryModel = selectedCategory
        item.currencyCode = currencyCode
        
        print("Updating transaction: \(transactionName), Amount: \(finalAmount) \(currencyCode), Date: \(date), Category: \(selectedCategory.displayText), Type: \(transactionType.rawValue)")
    }
    
    func resetForm() {
        transactionName = ""
        amount = 0.0
        transactionType = .expense
        currencyCode = UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
        date = Date()
        selectedCategory = nil
    }

}
