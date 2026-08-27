//
//  EditAddTransactionViewModel.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import Foundation
import SwiftData

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
    /// Transaction count per category, used to surface the most-used categories first in the compact
    /// picker. Empty until setTransactionViewModel() tallies it. [[category-usage-ordering]]
    var categoryUsage: [PersistentIdentifier: Int] = [:]
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

    // MARK: - Receipt scan

    /// What the last scan filled/couldn't read, shown as a one-line status under the form.
    /// nil when nothing has been scanned yet.
    var receiptStatusMessage: String?
    /// Populated only when the parser found several disagreeing total candidates — the form shows
    /// these as chips instead of guessing. Cleared once one is picked.
    var receiptTotalCandidates: [Decimal] = []
    /// The merchant string from the most recent scan, kept as the learning key even if the user
    /// later edits the Name field — a correction should still teach next time's category guess.
    private(set) var receiptMerchant: String?

    // A scanned field is "still showing what the scan set" — tracked by value equality against
    // what was written, not by intercepting edits. This means a rescan can safely overwrite its own
    // prior guess (the field still equals it) while never touching a value the user changed away
    // from it (equality breaks the moment they edit it). See applyReceiptScan().
    private var scanAppliedAmount: Double?
    private var scanAppliedDate: Date?
    private var scanAppliedCategoryId: PersistentIdentifier?
    private var scanAppliedName: String?

    var isAmountFromScan: Bool { scanAppliedAmount != nil && scanAppliedAmount == amount }
    var isDateFromScan: Bool { scanAppliedDate != nil && scanAppliedDate == date }
    var isCategoryFromScan: Bool { scanAppliedCategoryId != nil && scanAppliedCategoryId == selectedCategory?.persistentId }
    var isNameFromScan: Bool { scanAppliedName != nil && scanAppliedName == transactionName }

    let editingItem: TransactionSnapshot?
    let repo: any ITransactionRepository
    private let draft: TransactionDraft?

    /// The user-editable fields, snapshotted once loading finishes — lets `hasChanges` tell "the
    /// user actually touched something" apart from "the async category/goal load just hasn't
    /// finished yet". Edit mode only; stays nil in Add mode, where `hasChanges` isn't consulted.
    private struct FormSnapshot: Equatable {
        var name: String
        var amount: Double
        var type: TransactionType
        var date: Date
        var category: CategorySnapshot?
        var goal: GoalSnapshot?
    }
    private var originalFormSnapshot: FormSnapshot?
    private var currentFormSnapshot: FormSnapshot {
        FormSnapshot(name: transactionName, amount: amount, type: transactionType, date: date, category: selectedCategory, goal: selectedGoal)
    }

    /// Edit mode's nav-bar save button stays disabled until this is true — editing an existing
    /// transaction without changing anything has nothing to save. Always false in Add mode
    /// (`originalFormSnapshot` is never set there); callers should gate on `editingItem != nil`
    /// rather than relying on that, since it's an implementation detail of when the snapshot
    /// gets captured.
    var hasChanges: Bool {
        guard let originalFormSnapshot else { return false }
        return currentFormSnapshot != originalFormSnapshot
    }

    init(
        editingItem: TransactionSnapshot? = nil,
        draft: TransactionDraft? = nil,
        repo: any ITransactionRepository
    ) {
        self.editingItem = editingItem
        self.draft = draft
        self.repo = repo
        if let item = editingItem {
            populateForm(from: item)
        } else if let draft {
            populateForm(from: draft)
        }
    }

    func setTransactionViewModel() {
        Task {
            availableCategories = (try? await repo.fetchCategories()) ?? []
            availableGoals = (try? await repo.fetchGoals()) ?? []

            // Tally category usage so the compact picker can show the most-used first. One fetch on
            // open; fine for a personal dataset. ponytail: if this ever gets slow on huge histories,
            // move the count into the repository as a grouped query.
            let txns = (try? await repo.fetchAll()) ?? []
            var usage: [PersistentIdentifier: Int] = [:]
            for tx in txns { if let id = tx.categoryId { usage[id, default: 0] += 1 } }
            categoryUsage = usage

            // Set selectedCategory from editingItem.categoryId if editing
            if let catId = editingItem?.categoryId {
                selectedCategory = availableCategories.first { $0.persistentId == catId }
            } else if let draft {
                selectedCategory = availableCategories.first {
                    $0.name == draft.categoryName && $0.transactionType == draft.transactionType
                }
            }

            // Pre-select goal when editing a transfer
            if let editingItem = editingItem, let goalId = editingItem.goalId {
                selectedGoal = availableGoals.first { $0.id == goalId }
            }

            if editingItem == nil {
                currencyCode = UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
            } else {
                // Everything above (category/goal resolution included) has landed — this is the
                // form as loaded, before the user has touched anything.
                originalFormSnapshot = currentFormSnapshot
            }
        }
    }

    /// Transaction types offered in the picker. Transfer needs a goal to move money into, so it is
    /// hidden when there are no goals — unless the form is already on Transfer (editing an existing
    /// transfer, or goals still loading), so we never hide the currently-selected type.
    var availableTypes: [TransactionType] {
        if availableGoals.isEmpty && transactionType != .transfer {
            return TransactionType.allCases.filter { $0 != .transfer }
        }
        return TransactionType.allCases
    }

    /// Name is optional: a blank name renders the localized category as the title in the list
    /// (TransactionItemView), so validity is amount + a non-future date + a category (or a goal for
    /// transfers).
    var isFormValid: Bool {
        amount > 0 &&
        date <= Date.now &&
        (transactionType == .transfer ? selectedGoal != nil : selectedCategory != nil)
    }

    /// Widget reviews arrive with a complete draft. Keeping the keyboard closed lets
    /// the user inspect the populated transaction before deciding to save it.
    var shouldAutoFocusAmount: Bool {
        editingItem == nil && draft == nil
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

    /// Categories for the current type, most-used first (alphabetical tiebreak) so the common picks
    /// sit at the front of the compact horizontal picker.
    var filteredCategories: [CategorySnapshot] {
        availableCategories
            .filter { $0.transactionType == transactionType }
            .sorted { lhs, rhs in
                let l = categoryUsage[lhs.persistentId] ?? 0
                let r = categoryUsage[rhs.persistentId] ?? 0
                if l != r { return l > r }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func selectCreatedCategory(_ category: CategorySnapshot) {
        availableCategories.removeAll { $0.id == category.id }
        availableCategories.append(category)
        selectedCategory = category
    }

    /// Fills the form from a receipt scan. Only overwrites a field that's still at its default
    /// *or* still equal to what an earlier scan set — see the `scanApplied*`/`is*FromScan`
    /// properties above for why that single equality check covers both "untouched" and "rescan
    /// replaces its own prior guess" without ever touching a hand-typed value.
    func applyReceiptScan(_ scan: ReceiptScan, learnedMerchants: [String: UUID]) {
        var filled: [String] = []
        var notes: [String] = []
        receiptTotalCandidates = []

        let amountEditable = amount == 0 || isAmountFromScan
        if amountEditable {
            if let total = scan.total {
                amount = Double(truncating: total as NSDecimalNumber)
                scanAppliedAmount = amount
                filled.append(String(localized: "amount"))
            } else if !scan.totalCandidates.isEmpty {
                receiptTotalCandidates = scan.totalCandidates
            } else {
                notes.append(String(localized: "Couldn't read the amount"))
            }
        }

        let dateEditable = Calendar.current.isDateInToday(date) || isDateFromScan
        if dateEditable, !scan.dateWasClamped, let scannedDate = scan.date {
            date = scannedDate
            scanAppliedDate = scannedDate
            filled.append(String(localized: "date"))
        }
        if scan.dateWasClamped {
            notes.append(String(localized: "Couldn't read the date, using today"))
        }

        // Refund receipts flip the type to Income, but only while no category is picked yet —
        // TransactionFormView clears category/goal on type change, so flipping under an existing
        // pick would silently wipe it.
        if scan.isRefund, selectedCategory == nil, transactionType != .transfer {
            transactionType = .income
        }

        if let merchant = scan.merchant { receiptMerchant = merchant }

        let categoryEditable = selectedCategory == nil || isCategoryFromScan
        if categoryEditable, transactionType != .transfer {
            let inferred = ReceiptCategoryInferrer.infer(
                merchant: scan.merchant,
                transactionType: transactionType,
                categories: availableCategories,
                learnedMerchants: learnedMerchants,
                usage: categoryUsage
            )
            if let inferred {
                selectedCategory = inferred
                scanAppliedCategoryId = inferred.persistentId
                filled.append(String(localized: "category"))
            }
        }

        let nameEditable = transactionName.isEmpty || isNameFromScan
        if nameEditable, let merchant = scan.merchant {
            transactionName = merchant
            scanAppliedName = merchant
            filled.append(String(localized: "merchant"))
        }

        if filled.isEmpty && notes.isEmpty && receiptTotalCandidates.isEmpty {
            receiptStatusMessage = String(localized: "Couldn't read this receipt — try better light, or enter it manually")
        } else {
            var parts: [String] = []
            if !filled.isEmpty {
                parts.append(String(localized: "Filled \(filled.joined(separator: ", "))"))
            }
            parts.append(contentsOf: notes)
            receiptStatusMessage = parts.joined(separator: ". ")
        }
    }

    /// Called when the user taps a candidate chip to resolve an ambiguous total.
    func selectReceiptTotalCandidate(_ candidate: Decimal) {
        amount = Double(truncating: candidate as NSDecimalNumber)
        scanAppliedAmount = amount
        receiptTotalCandidates = []
    }

    /// Whenever a scan happened on this transaction, teach the merchant → category pairing from
    /// whatever category ends up selected at save time — including a user's correction, which is
    /// exactly the signal the learned tier needs. Never fires for a typed-only transaction (no
    /// `receiptMerchant`), since a hand-typed name is too inconsistent to learn from.
    func recordReceiptLearningIfNeeded() async {
        guard let receiptMerchant, let categoryId = selectedCategory?.id else { return }
        try? await repo.saveMerchantCategoryMapping(
            merchant: ReceiptCategoryInferrer.normalize(receiptMerchant),
            categoryId: categoryId
        )
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

    private func populateForm(from draft: TransactionDraft) {
        amount = draft.amount
        transactionName = draft.note
        transactionType = draft.transactionType
        currencyCode = draft.currencyCode
        date = draft.date
        // selectedCategory is resolved after the asynchronous category load.
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
        receiptStatusMessage = nil
        receiptTotalCandidates = []
        receiptMerchant = nil
        scanAppliedAmount = nil
        scanAppliedDate = nil
        scanAppliedCategoryId = nil
        scanAppliedName = nil
    }

}
