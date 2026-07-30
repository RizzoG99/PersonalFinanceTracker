//  BudgetRow.swift
//  PersonalFinanceTraker

import SwiftUI
import SwiftData

struct BudgetRow: View {
    @Bindable var category: CategoryModel
    var isFocused: FocusState<PersistentIdentifier?>.Binding
    @Environment(\.modelContext) private var modelContext
    @Environment(DataChangedSignal.self) private var dataChanged
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .foregroundStyle(category.categoryColor)
                .frame(width: 24)
            Text(category.name.localizedCategoryDisplay)
                .foregroundStyle(.textPrimary)
            Spacer()
            if !rowFocused && hasBudget {
                Circle()
                    .fill(.accentIndigo)
                    .frame(width: 6, height: 6)
            }
            TextField("No limit", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused(isFocused, equals: category.id)
                .frame(width: 100)
                .foregroundStyle(!rowFocused && hasBudget ? .accentIndigo : .textPrimary)
                .fontWeight(!rowFocused && hasBudget ? .medium : .regular)
                .accessibilityLabel("\(category.name) budget")
                .accessibilityValue(text.isEmpty ? "No limit" : text)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = category.id }
        .onAppear { text = displayText(for: category.monthlyBudget) }
        .onChange(of: rowFocused) { _, focused in
            if focused {
                text = rawText(for: category.monthlyBudget)
            } else {
                commit()
                text = displayText(for: category.monthlyBudget)
            }
        }
    }

    private var rowFocused: Bool {
        isFocused.wrappedValue == category.id
    }

    private var hasBudget: Bool {
        if let budget = category.monthlyBudget { return budget > 0 }
        return false
    }

    /// Formatted for resting display, matching how Dashboard shows the same value.
    private func displayText(for budget: Decimal?) -> String {
        guard let budget, budget > 0 else { return "" }
        return budget.formatted(.currency(code: "EUR"))
    }

    /// Unformatted digits for editing — what `commit()` can parse back.
    private func rawText(for budget: Decimal?) -> String {
        guard let budget, budget > 0 else { return "" }
        return NSDecimalNumber(decimal: budget).stringValue
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            category.monthlyBudget = nil
        } else if let value = AmountParser.parse(trimmed, requirePositive: true) {
            category.monthlyBudget = value
        } else {
            return  // invalid, non-empty: revert — do not touch the model
        }
        try? modelContext.save()
        dataChanged.bump()
    }
}
