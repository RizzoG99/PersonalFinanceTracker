//  BudgetRow.swift
//  PersonalFinanceTraker

import SwiftUI
import SwiftData

struct BudgetRow: View {
    @Bindable var category: CategoryModel
    @Environment(\.modelContext) private var modelContext
    @Environment(DataChangedSignal.self) private var dataChanged
    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .foregroundStyle(category.categoryColor)
                .frame(width: 24)
            Text(category.name)
                .foregroundStyle(.textPrimary)
            Spacer()
            TextField("No limit", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .frame(width: 100)
                .foregroundStyle(.textPrimary)
        }
        .onAppear { text = displayText(for: category.monthlyBudget) }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private func displayText(for budget: Decimal?) -> String {
        guard let budget, budget > 0 else { return "" }
        return NSDecimalNumber(decimal: budget).stringValue
    }

    private func commit() {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        if let value = Decimal(string: normalized), value > 0 {
            category.monthlyBudget = value
        } else {
            category.monthlyBudget = nil
            text = ""
        }
        try? modelContext.save()
        dataChanged.bump()
    }
}
