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
            TransactionFormView(viewModel: viewModel)
            TransactionSaveButton(
                title: viewModel.editingItem == nil ? "Add Transaction" : "Update Transaction",
                isValid: viewModel.isFormValid,
                action: saveTransaction
            )
        }
        .navigationTitle(viewModel.editingItem == nil ? "New Transaction" : "Edit Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.setTransactionViewModel(transactionViewModel)
        }
    }

    private func saveTransaction() {
        if viewModel.editingItem == nil {
            if let newItem = viewModel.getTransactionData() {
                transactionViewModel.add(newItem)
                dismiss()
            }
        } else {
            viewModel.updateTransaction()
            transactionViewModel.update()
            dismiss()
        }
    }
}
