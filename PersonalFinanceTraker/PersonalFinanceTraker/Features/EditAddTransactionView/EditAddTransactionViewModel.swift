//
//  EditAddTransactionViewModel.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import Foundation

@Observable @MainActor
final class EditAddTransactionViewModel {
    var transactionName: String = ""
    var amount: Double = 0.0
    var transactionType: TransactionType = .expense
    var currencyCode: String = "EUR"
    var date: Date = Date.now
    var selectedCategory: CategorySnapshot?
    var availableCategories: [CategorySnapshot] = []
    var availableGoals: [GoalSnapshot] = []
    var selectedGoal: GoalSnapshot?
    var showingDatePicker: Bool = false
    var showingCategoryPicker: Bool = false
    var showingErrorAlert: Bool = false
    var errorMessage: String = ""
    var isRecurring: Bool = false
    var recurrenceFrequency: RecurrenceFrequency = .monthly
    var recurrenceInterval: Int = 1
    /// When on, saving reopens a blank form in place instead of dismissing, so the
    /// user can log several in a row. Session-only, Add-mode only. Deliberately NOT
    /// touched by resetForm() — it must survive across the sequential saves.
    var addAnother: Bool = false

    let editingItem: TransactionSnapshot?
    let repo: any ITransactionRepository

    init(editingItem: TransactionSnapshot? = nil, repo: any ITransactionRepository) {
        self.editingItem = editingItem
        self.repo = repo
        if let item = editingItem {
            populateForm(from: item)
        }
    }

    func setTransactionViewModel() {
        Task {
            availableCategories = (try? await repo.fetchCategories()) ?? []
            availableGoals = (try? await repo.fetchGoals()) ?? []

            // Set selectedCategory from editingItem.categoryId if editing
            if let catId = editingItem?.categoryId {
                selectedCategory = availableCategories.first { $0.persistentId == catId }
            }

            // Pre-select goal when editing a transfer
            if let editingItem = editingItem, let goalId = editingItem.goalId {
                selectedGoal = availableGoals.first { $0.id == goalId }
            }

            if editingItem == nil {
                currencyCode = UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
            }
        }
    }

    var isFormValid: Bool {
        !transactionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        amount > 0 &&
        date <= Date.now &&
        (transactionType == .transfer ? selectedGoal != nil : selectedCategory != nil)
    }

    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return Self.mediumDateFormatter.string(from: date)
    }

    var filteredCategories: [CategorySnapshot] {
        availableCategories.filter { $0.transactionType == transactionType }
    }

    func buildInput() -> TransactionInput? {
        guard amount > 0 else { return nil }
        if transactionType == .transfer {
            guard selectedGoal != nil else { return nil }
        } else {
            guard selectedCategory != nil else { return nil }
        }
        // expenses and transfers stored negative, income positive
        let finalAmount = transactionType == .income ? Decimal(amount) : -Decimal(amount)
        // transfers have no category; label them by their goal
        let categoryLabel = transactionType == .transfer
            ? selectedGoal.map { "→ \($0.name)" } ?? ""
            : selectedCategory?.name ?? ""
        return TransactionInput(
            timestamp: date,
            amount: finalAmount,
            note: transactionName,
            category: categoryLabel,
            currencyCode: currencyCode,
            goalId: selectedGoal?.id,
            categoryPersistentId: selectedCategory?.persistentId
        )
    }

    /// nil when not recurring, editing an existing transaction, or the type is Transfer
    /// (goal-linked recurrence is deferred — see docs/superpowers/specs/2026-08-02-recurring-transactions-design.md).
    func buildRecurrenceRuleInput() -> RecurrenceRuleInput? {
        guard isRecurring, editingItem == nil, transactionType != .transfer,
              let input = buildInput() else { return nil }
        return RecurrenceRuleInput(
            frequency: recurrenceFrequency,
            interval: recurrenceInterval,
            startDate: input.timestamp,
            amount: input.amount,
            note: input.note,
            category: input.category,
            currencyCode: input.currencyCode,
            goalId: input.goalId,
            categoryPersistentId: input.categoryPersistentId
        )
    }

    /// Used for "this and future" edits: keeps the rule's cadence (frequency/interval/startDate)
    /// untouched — v1's edit form never shows those fields, and changing startDate would shift
    /// every future occurrence date — and applies only the template fields visible in the form.
    func buildRecurrenceRuleInput(preserving rule: RecurrenceRuleSnapshot) -> RecurrenceRuleInput? {
        guard let input = buildInput() else { return nil }
        return RecurrenceRuleInput(
            id: rule.id,
            frequency: rule.frequency,
            interval: rule.interval,
            startDate: rule.startDate,
            amount: input.amount,
            note: input.note,
            category: input.category,
            currencyCode: input.currencyCode,
            goalId: input.goalId,
            categoryPersistentId: input.categoryPersistentId
        )
    }

    /// Creates the rule and immediately materializes its first occurrence, so the new
    /// transaction is visible right away instead of waiting for the next launch/foreground pass.
    func saveRecurringTransaction() async throws {
        guard let ruleInput = buildRecurrenceRuleInput() else { return }
        try await repo.addRecurrenceRule(ruleInput)
        let firstOccurrence = TransactionInput(
            timestamp: ruleInput.startDate,
            amount: ruleInput.amount,
            note: ruleInput.note,
            category: ruleInput.category,
            currencyCode: ruleInput.currencyCode,
            goalId: ruleInput.goalId,
            categoryPersistentId: ruleInput.categoryPersistentId,
            recurrenceRuleId: ruleInput.id
        )
        try await repo.materializeOccurrences(ruleId: ruleInput.id, inputs: [firstOccurrence], newCursor: ruleInput.startDate)
    }

    func saveTransaction() {
        guard let input = buildInput() else { return }
        Task {
            if let existing = editingItem {
                try? await repo.update(id: existing.id, with: input)
            } else {
                try? await repo.add(input)
            }
        }
    }

    private func populateForm(from item: TransactionSnapshot) {
        date = item.timestamp
        amount = abs(Double(truncating: item.amount as NSDecimalNumber))
        transactionName = item.note
        currencyCode = item.currencyCode

        let type: TransactionType = item.goalId != nil ? .transfer
            : item.amount < 0 ? .expense : .income
        transactionType = type

        // selectedCategory set in setTransactionViewModel() after categories load
    }

    func resetForm() {
        transactionName = ""
        amount = 0
        transactionType = .expense
        currencyCode = UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
        date = Date()
        selectedCategory = nil
        selectedGoal = nil
        isRecurring = false
        recurrenceFrequency = .monthly
        recurrenceInterval = 1
    }

}
