//
//  ImportCategorySetupSheet.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct ImportCategorySetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    let csvCategory: String
    let lockedType: TransactionType?
    let existingNames: Set<String>
    let otherDraftNames: Set<String>
    let onSave: (ImportCategoryDraft) -> Void

    @State private var draft: ImportCategoryDraft

    init(
        draft: ImportCategoryDraft,
        lockedType: TransactionType?,
        existingNames: Set<String>,
        otherDraftNames: Set<String>,
        onSave: @escaping (ImportCategoryDraft) -> Void
    ) {
        self.csvCategory = draft.csvCategory
        self.lockedType = lockedType
        self.existingNames = existingNames
        self.otherDraftNames = otherDraftNames
        self.onSave = onSave
        var initialDraft = draft
        if let lockedType {
            initialDraft.type = lockedType
        }
        _draft = State(initialValue: initialDraft)
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespaces)
    }

    private var nameError: String? {
        guard !trimmedName.isEmpty else { return nil }
        if !CategoryNameValidator.isValid(trimmedName) {
            return "Use letters, numbers, spaces, and common punctuation"
        }
        let normalizedName = trimmedName.lowercased()
        if existingNames.contains(normalizedName) || otherDraftNames.contains(normalizedName) {
            return "A category with this name already exists"
        }
        return nil
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && nameError == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("CSV Category") {
                    Text(csvCategory)
                        .foregroundStyle(.secondary)
                }
                .appFormSectionBackground()

                Section("Name") {
                    TextField("Category name", text: $draft.name)
                        .autocorrectionDisabled()
                    if let nameError {
                        Text(nameError)
                            .font(.caption)
                            .foregroundStyle(.negative)
                    }
                }
                .appFormSectionBackground()

                Section {
                    Picker("Type", selection: $draft.type) {
                        Text("Expense").tag(TransactionType.expense)
                        Text("Income").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    .disabled(lockedType != nil)
                } header: {
                    Text("Type")
                }
                footer: {
                    if lockedType != nil {
                        Text("The CSV transaction type determines this category's type.")
                    }
                }
                .appFormSectionBackground()

                Section("Color") {
                    ColorTokenPicker(selectedToken: $draft.colorToken)
                }
                .appFormSectionBackground()

                Section("Icon") {
                    IconGridPicker(selectedSymbol: $draft.systemImage, colorToken: draft.colorToken)
                }
                .appFormSectionBackground()
            }
            .appFormBackground()
            .background { AppBackground() }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.name = trimmedName
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationBackground { AppBackground() }
    }
}
