//
//  TransactionView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import SwiftUI
import SwiftData

struct EditAddTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var transactionViewModel: TransactionListViewModel
    @StateObject private var viewModel: EditAddTransactionViewModel
    
    private let transaction: TransactionModel?
    
    init(_ transaction: TransactionModel) {
        self.transaction = transaction
        _viewModel = StateObject(wrappedValue: EditAddTransactionViewModel(transaction: transaction))
    }
    
    init() {
        self.transaction = nil
        _viewModel = StateObject(wrappedValue: EditAddTransactionViewModel())
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    // Transaction Type Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Transaction Type", selection: $viewModel.transactionType) {
                            ForEach(TransactionType.allCases, id: \.self) { type in
                                VStack {
                                    Text(type.rawValue)
                                }
                                .tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: viewModel.transactionType) { _, _ in
                            // Reset category when type changes
                            viewModel.selectedCategory = nil
                        }
                    }
                    
                    // Transaction Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        TextField("Enter transaction name", text: $viewModel.transactionName)
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
                                viewModel.showingDatePicker.toggle()
                            }) {
                                HStack {
                                    Text(viewModel.formattedDate)
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
                                viewModel.showingCategoryPicker.toggle()
                            }) {
                                HStack {
                                    if let selectedCategory = viewModel.selectedCategory {
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
                                        .stroke(viewModel.selectedCategory == nil ? Color.red.opacity(0.5) : Color(.systemGray4), lineWidth: 1)
                                )
                            }
                        }
                    }
                    
                    // Amount
                    CurrencyAmountField(
                        label: "Amount",
                        placeholder: "0",
                        amount: $viewModel.amount
                    )
                    
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Save/Update Transaction Button
                Button(action: {
                    if viewModel.editingItem == nil {
                        addTransaction()
                    } else {
                        updateTransaction()
                    }
                }) {
                    HStack {
                        Image(systemName: viewModel.editingItem == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                        Text(viewModel.editingItem == nil ? "Add Transaction" : "Update Transaction")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isFormValid ? Color.blue : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!viewModel.isFormValid)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle(viewModel.editingItem == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.editingItem != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingDatePicker) {
                NavigationStack {
                    VStack {
                        DatePicker(
                            "Select Date",
                            selection: $viewModel.date,
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
                                viewModel.showingDatePicker = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $viewModel.showingCategoryPicker) {
                NavigationStack {
                    List {
                        ForEach(viewModel.filteredCategories) { category in
                            Button(action: {
                                viewModel.selectedCategory = category
                                viewModel.showingCategoryPicker = false
                            }) {
                                HStack {
                                    Text(category.displayText)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if viewModel.selectedCategory?.id == category.id {
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
                                viewModel.showingCategoryPicker = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .onTapGesture {
                // Dismiss keyboard when tapping outside - handled by the system
            }
        }
    }
    
    
    
    private func addTransaction() {
        if let newItem = viewModel.getTransactionData() {
            transactionViewModel.add(newItem)
            dismiss()
        }
    }
    
    private func updateTransaction() {
        viewModel.updateTransaction()
        // Save the context
        transactionViewModel.update()
        dismiss()
    }
}

//#Preview("New Transaction") {
//    EditAddTransactionView()
//        .modelContainer(for: TransactionModel.self, inMemory: true)
//}
//
//#Preview("Edit Transaction") {
//    let container = try! ModelContainer(for: TransactionModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
//    let sampleItem = TransactionModel(
//        timestamp: Date(),
//        amount: Decimal(-25.50),
//        note: "Coffee Shop",
//        category: "☕ Coffee & Drinks"
//    )
//    container.mainContext.insert(sampleItem)
//    
//    return EditAddTransactionView(transaction: sampleItem)
//        .environment(EditAddTransactionViewModel())
//        .modelContainer(container)
//}
