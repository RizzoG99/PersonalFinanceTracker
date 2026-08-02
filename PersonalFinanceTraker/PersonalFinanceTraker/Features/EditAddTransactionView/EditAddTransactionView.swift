//
//  TransactionView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import SwiftUI
import SwiftData

private enum PendingRecurrenceAction {
    case save(TransactionInput)
    case delete
}

private enum RecurrenceEditScope {
    case thisOnly
    case thisAndFuture
}

struct EditAddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataChangedSignal.self) private var dataChanged
    @State private var viewModel: EditAddTransactionViewModel
    @State private var pendingRecurrenceAction: PendingRecurrenceAction?
    private let materializationService = RecurrenceMaterializationService()

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
        .confirmationDialog(
            "This is part of a recurring series",
            isPresented: Binding(
                get: { pendingRecurrenceAction != nil },
                set: { if !$0 { pendingRecurrenceAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("This transaction") { applyPendingAction(scope: .thisOnly) }
            Button("This and future", role: .destructive) { applyPendingAction(scope: .thisAndFuture) }
            Button("Cancel", role: .cancel) { pendingRecurrenceAction = nil }
        }
    }

    private func saveTransaction() {
        guard let existing = viewModel.editingItem else {
            Task {
                if viewModel.isRecurring {
                    try? await viewModel.saveRecurringTransaction()
                } else if let input = viewModel.buildInput() {
                    try? await viewModel.repo.add(input)
                }
                dataChanged.bump()
                dismiss()
            }
            return
        }
        guard let input = viewModel.buildInput() else { return }
        if existing.recurrenceRuleId != nil {
            pendingRecurrenceAction = .save(input)
        } else {
            Task {
                try? await viewModel.repo.update(id: existing.id, with: input)
                dataChanged.bump()
                dismiss()
            }
        }
    }

    private func deleteTransaction() {
        guard let existing = viewModel.editingItem else { return }
        if existing.recurrenceRuleId != nil {
            pendingRecurrenceAction = .delete
        } else {
            Task {
                try? await viewModel.repo.delete(id: existing.id)
                dataChanged.bump()
                dismiss()
            }
        }
    }

    private func applyPendingAction(scope: RecurrenceEditScope) {
        guard let action = pendingRecurrenceAction,
              let existing = viewModel.editingItem,
              let ruleId = existing.recurrenceRuleId else {
            pendingRecurrenceAction = nil
            return
        }
        pendingRecurrenceAction = nil
        Task {
            switch (action, scope) {
            case (.save(let input), .thisOnly):
                try? await viewModel.repo.update(id: existing.id, with: input)

            case (.save, .thisAndFuture):
                if let rule = try? await viewModel.repo.fetchRecurrenceRule(id: ruleId),
                   let ruleInput = viewModel.buildRecurrenceRuleInput(preserving: rule) {
                    try? await viewModel.repo.updateRecurrenceRule(id: ruleId, with: ruleInput)
                    try? await viewModel.repo.deleteOccurrences(recurrenceRuleId: ruleId, from: existing.timestamp)
                    // deleteOccurrences just removed the row being edited (its timestamp >= cutoff) along
                    // with any later ones. Re-materialize immediately — dismissing this sheet is neither a
                    // launch nor a foreground transition, so without this call the edited transaction would
                    // stay missing from Activity until the user backgrounds/relaunches the app.
                    try? await materializationService.materialize(using: viewModel.repo)
                }

            case (.delete, .thisOnly):
                try? await viewModel.repo.delete(id: existing.id)

            case (.delete, .thisAndFuture):
                let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: existing.timestamp) ?? existing.timestamp
                try? await viewModel.repo.closeRecurrenceRule(id: ruleId, endDate: dayBefore)
                try? await viewModel.repo.deleteOccurrences(recurrenceRuleId: ruleId, from: existing.timestamp)
            }
            dataChanged.bump()
            dismiss()
        }
    }
}
