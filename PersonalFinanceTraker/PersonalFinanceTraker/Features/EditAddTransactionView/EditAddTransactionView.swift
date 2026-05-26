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
        VStack(spacing: 24) {
            formFields
            saveButton
        }
        .navigationTitle(viewModel.editingItem == nil ? "New Transaction" : "Edit Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.setTransactionViewModel(transactionViewModel)
        }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section {
                    CurrencyAmountField(
                        label: "Amount",
                        placeholder: "0",
                        amount: $viewModel.amount,
                        currencyCode: $viewModel.currencyCode
                    )
                }
                .appFormSectionBackground()

                Section {
                    TextField("Note", text: $viewModel.transactionName, prompt: Text("Note"))
                        .submitLabel(.next)
                }
                .appFormSectionBackground()

                Section {
                    dateField

                    Picker("Transaction Type", selection: $viewModel.transactionType) {
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .onChange(of: viewModel.transactionType) { _, _ in
                        viewModel.selectedCategory = nil
                    }

                    categoryField

                    Picker("Currency", selection: $viewModel.currencyCode) {
                        ForEach(["EUR", "USD", "GBP", "JPY", "AUD", "CAD", "CHF", "CNY"], id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .tint(.accentIndigo)
                }
                .appFormSectionBackground()
            }
            .appFormBackground()
        }
    }

    private var dateField: some View {
        DatePicker(
            "Date",
            selection: $viewModel.date,
            displayedComponents: [.date]
        )
        .tint(.accentIndigo)
    }

    private var categoryField: some View {
        Picker("Category", selection: $viewModel.selectedCategory) {
            Text("Select a category").tag(CategoryModel?.none)
            ForEach(viewModel.filteredCategories) { category in
                Text(category.name)
                    .tag(CategoryModel?.some(category))
            }
        }
        .tint(viewModel.selectedCategory == nil ? .secondary : .accentIndigo)
    }

    private var saveButton: some View {
        Button(action: {
            if viewModel.editingItem == nil {
                addTransaction()
            } else {
                updateTransaction()
            }
        }) {
            Text(viewModel.editingItem == nil ? "Add Transaction" : "Update Transaction")
            .font(.headline)
            .foregroundStyle(.textPrimary)
            .frame(maxWidth: .infinity)
            .padding()
            .glassEffect(.regular.tint(viewModel.isFormValid ? Color.accentIndigo : Color.gray).interactive())
        }
        .disabled(!viewModel.isFormValid)
        .padding(.horizontal)
        .padding(.bottom)
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
