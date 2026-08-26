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
    @State private var showingDeleteConfirmation = false
    @State private var refocusToken = 0
    @State private var savedCount = 0
    @State private var showSavedToast = false
    @State private var didFocusOnAmount = false
    @State private var toastTask: Task<Void, Never>?
    private let materializationService: RecurrenceMaterializationService

    init(
        _ snapshot: TransactionSnapshot? = nil,
        draft: TransactionDraft? = nil,
        repo: any ITransactionRepository,
        materializationService: RecurrenceMaterializationService,
        // Lets RecurringView's "+" open this sheet with Repeat already on, matching the
        // context the user tapped it from. Add-mode only in practice — nothing sets this
        // alongside `snapshot`.
        presetRecurring: Bool = false
    ) {
        let vm = EditAddTransactionViewModel(editingItem: snapshot, draft: draft, repo: repo)
        if presetRecurring { vm.isRecurring = true }
        _viewModel = State(wrappedValue: vm)
        self.materializationService = materializationService
    }

    var body: some View {
        TransactionFormView(viewModel: viewModel, focusTrigger: refocusToken)
        .readableWidth()
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
            // No other dismissal affordance exists on this sheet besides swipe-down — give it an
            // explicit, discoverable exit (Nielsen: user control and freedom).
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            // Lives in the nav bar (not a pinned button above the keyboard) so it's never in a
            // fight with the keyboard's own accessory bar for screen space — same pattern as
            // Notes/Reminders. Used to be landscape-only; the portrait pinned-bar alternative was
            // tried and rejected (kept getting covered by, or visually clashing with, the
            // keyboard toolbar), so this is now unconditional.
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveTransaction()
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel(viewModel.editingItem == nil ? "Add Transaction" : "Update Transaction")
                // Edit mode: nothing to save until the user changes something. Add mode is
                // unaffected — isFormValid alone already gates it there.
                .disabled(!viewModel.isFormValid || (viewModel.editingItem != nil && !viewModel.hasChanges))
            }
            if viewModel.editingItem != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        requestDeleteTransaction()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    // A non-recurring transaction used to be removed immediately from the
                    // toolbar, beside Save. Keep deletion one deliberate step away from the
                    // primary edit action; recurring transactions present their scope chooser
                    // instead.
                    .confirmationDialog(
                        "Delete this transaction?",
                        isPresented: $showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            deleteTransaction()
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This action cannot be undone.")
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

    private func requestDeleteTransaction() {
        guard let existing = viewModel.editingItem else { return }
        if existing.recurrenceRuleId != nil {
            deleteTransaction()
        } else {
            showingDeleteConfirmation = true
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
