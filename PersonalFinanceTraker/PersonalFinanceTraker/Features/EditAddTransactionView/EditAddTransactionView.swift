//
//  TransactionView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import SwiftUI
import SwiftData

struct EditAddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataChangedSignal.self) private var dataChanged
    @State private var viewModel: EditAddTransactionViewModel

    init(_ snapshot: TransactionSnapshot? = nil, repo: any ITransactionRepository) {
        _viewModel = State(wrappedValue: EditAddTransactionViewModel(editingItem: snapshot, repo: repo))
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
            if viewModel.editingItem != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        deleteTransaction()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .onAppear {
            viewModel.setTransactionViewModel()
        }
    }

    private func saveTransaction() {
        Task {
            if let existing = viewModel.editingItem {
                if let input = viewModel.buildInput() {
                    try? await viewModel.repo.update(id: existing.id, with: input)
                }
            } else if viewModel.isRecurring {
                try? await viewModel.saveRecurringTransaction()
            } else if let input = viewModel.buildInput() {
                try? await viewModel.repo.add(input)
            }
            dataChanged.bump()
            dismiss()
        }
    }

    private func deleteTransaction() {
        guard let existing = viewModel.editingItem else { return }
        Task {
            try? await viewModel.repo.delete(id: existing.id)
            dataChanged.bump()
            dismiss()
        }
    }
}
