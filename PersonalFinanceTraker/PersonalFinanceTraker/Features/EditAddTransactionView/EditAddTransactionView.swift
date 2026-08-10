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
    @State private var refocusToken = 0
    @State private var savedCount = 0
    @State private var showSavedToast = false
    @State private var toastTask: Task<Void, Never>?
    private let materializationService: RecurrenceMaterializationService

    init(_ snapshot: TransactionSnapshot? = nil, repo: any ITransactionRepository, materializationService: RecurrenceMaterializationService) {
        _viewModel = State(wrappedValue: EditAddTransactionViewModel(editingItem: snapshot, repo: repo))
        self.materializationService = materializationService
    }

    var body: some View {
        VStack(spacing: 24) {
            TransactionFormView(viewModel: viewModel, focusTrigger: refocusToken)
            VStack(spacing: 12) {
                // Pinned above the button (Add mode only): the mode and the action it changes share
                // one persistent, thumb-reachable zone, instead of the toggle being buried in the scroll.
                if viewModel.editingItem == nil {
                    Toggle(String(localized: "Add another"), isOn: $viewModel.addAnother)
                        .tint(.accentIndigo)
                        .padding(.horizontal)
                }
                TransactionSaveButton(
                    title: viewModel.editingItem == nil ? "Add Transaction" : "Update Transaction",
                    isValid: viewModel.isFormValid,
                    action: saveTransaction
                )
            }
        }
        .sensoryFeedback(.success, trigger: savedCount)
        .overlay(alignment: .top) {
            if showSavedToast {
                ToastBanner(icon: "checkmark.circle.fill", message: String(localized: "Transaction saved")) {
                    EmptyView()
                }
                .accessibilityElement(children: .combine)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: showSavedToast)
        .navigationTitle(viewModel.editingItem == nil ? "New Transaction" : "Edit Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Recurrence is a rare setup action, so it lives as a nav-bar toggle instead of taking
            // inline form space. Add mode only, and not for transfers (recurring transfers are
            // deferred — matches the type-change guard that also clears isRecurring).
            if viewModel.editingItem == nil && viewModel.transactionType != .transfer {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.isRecurring.toggle()
                    } label: {
                        Label("Repeat", systemImage: viewModel.isRecurring ? "repeat.circle.fill" : "repeat")
                    }
                    // Indigo only when on; a neutral glyph when off so the toolbar button doesn't
                    // read as "active" while recurrence is actually off.
                    .tint(viewModel.isRecurring ? Color.accentIndigo : Color.primary)
                    .accessibilityValue(viewModel.isRecurring ? String(localized: "On") : String(localized: "Off"))
                }
            }
            if viewModel.editingItem != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        deleteTransaction()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .confirmationDialog(
                        "This is part of a recurring series",
                        isPresented: Binding(
                            get: { pendingRecurrenceAction != nil },
                            set: { if !$0 { pendingRecurrenceAction = nil } }
                        ),
                        titleVisibility: .visible
                    ) {
                        Button("This transaction", role: .destructive) { applyPendingAction(scope: .thisOnly) }
                        Button("This and future", role: .destructive) { applyPendingAction(scope: .thisAndFuture) }
                        Button("Cancel", role: .cancel) { pendingRecurrenceAction = nil }
                    }
                }
            }
        }
        .onAppear {
            viewModel.setTransactionViewModel()
        }
    }

    private func saveTransaction() {
        guard let existing = viewModel.editingItem else {
            Task {
                do {
                    if viewModel.isRecurring {
                        try await viewModel.saveRecurringTransaction()
                    } else {
                        // Guard nil (don't `else if`): a nil input must not fall through
                        // to the success path and show a false "saved". isFormValid gates
                        // the button, so this is defensive but explicit.
                        guard let input = viewModel.buildInput() else { return }
                        try await viewModel.repo.add(input)
                    }
                    dataChanged.bump()
                    if viewModel.addAnother {
                        viewModel.resetForm()
                        savedCount += 1     // fires .sensoryFeedback(.success)
                        refocusToken += 1   // clears + re-focuses Amount (Task 2)
                        flashSavedToast()
                    } else {
                        dismiss()
                    }
                } catch {
                    // Keep the filled form; surface the existing error alert. No toast/haptic.
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.showingErrorAlert = true
                }
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

    private func flashSavedToast() {
        toastTask?.cancel()
        showSavedToast = true
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { showSavedToast = false }
        }
    }
}
