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
    @Environment(TransactionListViewModel.self) private var transactionViewModel
    @Environment(DashboardViewModel.self) private var dashboardViewModel
    @State private var viewModel: EditAddTransactionViewModel

    private let transaction: TransactionModel?

    init(_ transaction: TransactionModel) {
        self.transaction = transaction
        _viewModel = State(wrappedValue: EditAddTransactionViewModel(transaction: transaction))
    }

    init() {
        self.transaction = nil
        _viewModel = State(wrappedValue: EditAddTransactionViewModel())
    }

    var body: some View {
        VStack(spacing: 24) {
            TransactionFormView(viewModel: viewModel)
            TransactionSaveButton(
                title: viewModel.editingItem == nil ? "Add Transaction" : "Update Transaction",
                isValid: viewModel.isFormValid,
                action: saveTransaction
            )
        }
        .navigationTitle(viewModel.editingItem == nil ? "New Transaction" : "Edit Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let transaction {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        transactionViewModel.delete(transaction)
                        dashboardViewModel.load()
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .onAppear {
            viewModel.setTransactionViewModel(transactionViewModel)
        }
    }

    private func saveTransaction() {
        if viewModel.editingItem == nil {
            if let newItem = viewModel.getTransactionData() {
                transactionViewModel.add(newItem)
                dashboardViewModel.load()
                dismiss()
            }
        } else {
            viewModel.updateTransaction()
            transactionViewModel.update()
            dashboardViewModel.load()
            dismiss()
        }
    }
}
