//
//  TransactionView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import SwiftUI
import SwiftData

struct TransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var transactionName: String = ""
    @State private var amount: Double = 0.0 // Changed from Decimal to Double for CurrencyAmountField
    @State private var transactionType: TransactionType = .expense
    @State private var date: Date = Date()
    @State private var selectedCategory: TransactionCategory?
    @State private var showingDatePicker: Bool = false
    @State private var showingCategoryPicker: Bool = false
    @State private var showingErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    // Store the item being edited (nil for new transaction)
    private let editingItem: TransactionModel?
    
    init(transaction: TransactionModel) {
        self.editingItem = transaction
        let transactionType: TransactionType = transaction.amount < 0 ? .expense : .income
        let categoryType = transactionType == .expense ? TransactionCategory.expenseCategories : TransactionCategory.incomeCategories
        
        self._transactionName = State(initialValue: transaction.note)
        self._amount = State(initialValue: abs(Double(truncating: transaction.amount as NSDecimalNumber)))
        self._transactionType = State(initialValue: transactionType)
        self._date = State(initialValue: transaction.timestamp)
        self._selectedCategory = State(initialValue: categoryType.first(where: { transaction.category.contains($0.emoji) }))
    }
    
    init() {
        self.editingItem = nil
    }
    
    private var isFormValid: Bool {
        !transactionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
        amount > 0 && 
        date <= Date() &&
        selectedCategory != nil
    }
    
    private var formattedDate: String {
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
    
    private var filteredCategories: [TransactionCategory] {
        TransactionCategory.defaultCategories.filter { category in
            switch transactionType {
            case .income:
                return TransactionCategory.incomeCategories.contains { $0.id == category.id }
            case .expense:
                return TransactionCategory.expenseCategories.contains { $0.id == category.id }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    // Transaction Type Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Transaction Type", selection: $transactionType) {
                            ForEach(TransactionType.allCases, id: \.self) { type in
                                VStack {
                                    Text(type.rawValue)
                                }
                                .tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: transactionType) { _, _ in
                            // Reset category when type changes
                            selectedCategory = nil
                        }
                    }
                    
                    // Transaction Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        TextField("Enter transaction name", text: $transactionName)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.next)
                            .onSubmit {
                                // Focus can be handled by the reusable component if needed
                            }
                    }
                    
                    // Date
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Date")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            
                            Button(action: {
                                showingDatePicker.toggle()
                            }) {
                                HStack {
                                    Text(formattedDate)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "calendar")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.systemGray4), lineWidth: 1)
                                )
                            }
                        }
                        
                        // Category
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Category")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            
                            Button(action: {
                                showingCategoryPicker.toggle()
                            }) {
                                HStack {
                                    if let selectedCategory = selectedCategory {
                                        Text(selectedCategory.displayText)
                                            .foregroundStyle(.primary)
                                    } else {
                                        Text("Select a category")
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedCategory == nil ? Color.red.opacity(0.5) : Color(.systemGray4), lineWidth: 1)
                                )
                            }
                        }
                    }
                    
                    // Amount
                    CurrencyAmountField(
                        label: "Amount",
                        placeholder: "0",
                        amount: $amount
                    )
                    
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Save/Update Transaction Button
                Button(action: {
                    if editingItem == nil {
                        addTransaction()
                    } else {
                        updateTransaction()
                    }
                }) {
                    HStack {
                        Image(systemName: editingItem == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                        Text(editingItem == nil ? "Add Transaction" : "Update Transaction")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isFormValid ? Color.blue : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!isFormValid)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle(editingItem == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if editingItem != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    VStack {
                        DatePicker(
                            "Select Date",
                            selection: $date,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .padding()
                        
                        Spacer()
                    }
                    .navigationTitle("Select Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingDatePicker = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
                    .sheet(isPresented: $showingCategoryPicker) {
                NavigationStack {
                    List {
                        ForEach(filteredCategories) { category in
                            Button(action: {
                                selectedCategory = category
                                showingCategoryPicker = false
                            }) {
                                HStack {
                                    Text(category.displayText)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedCategory?.id == category.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                            .font(.headline)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .navigationTitle("Select Category")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingCategoryPicker = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .onTapGesture {
                // Dismiss keyboard when tapping outside - handled by the system
            }
            .alert("Error Saving Transaction", isPresented: $showingErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }


    
    private func addTransaction() {
        guard let selectedCategory = selectedCategory else { return }
        
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
        modelContext.insert(newItem)
        
        // Save the context
        do {
            try modelContext.save()
            // If save is successful, reset form and dismiss the view
            resetForm()
            dismiss()
        } catch {
            // If save fails, show an error alert
            errorMessage = "Failed to save transaction: \(error.localizedDescription)"
            showingErrorAlert = true
            print("Error saving transaction: \(error)")
        }
    }
    
    private func updateTransaction() {
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
        
        // Save the context
        do {
            try modelContext.save()
            // If save is successful, dismiss the view
            dismiss()
        } catch {
            // If save fails, show an error alert
            errorMessage = "Failed to update transaction: \(error.localizedDescription)"
            showingErrorAlert = true
            print("Error updating transaction: \(error)")
        }
    }
    
    private func resetForm() {
        transactionName = ""
        amount = 0.0
        transactionType = .expense
        date = Date()
        selectedCategory = nil
    }
}

#Preview("New Transaction") {
    TransactionView()
        .modelContainer(for: TransactionModel.self, inMemory: true)
}

#Preview("Edit Transaction") {
    let container = try! ModelContainer(for: TransactionModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let sampleItem = TransactionModel(
        timestamp: Date(),
        amount: Decimal(-25.50),
        note: "Coffee Shop",
        category: "☕ Coffee & Drinks"
    )
    container.mainContext.insert(sampleItem)
    
    return TransactionView(transaction: sampleItem)
        .modelContainer(container)
}
