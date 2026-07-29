//  BudgetsView.swift
//  PersonalFinanceTraker

import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Query(sort: \CategoryModel.name) private var categories: [CategoryModel]
    @FocusState private var focusedCategoryID: PersistentIdentifier?

    private var expenseCategories: [CategoryModel] {
        categories.filter { $0.transactionType == .expense }
    }

    private var totalBudgeted: Decimal {
        expenseCategories.compactMap(\.monthlyBudget).filter { $0 > 0 }.reduce(0, +)
    }

    var body: some View {
        List {
            Section {
                ForEach(expenseCategories) { category in
                    BudgetRow(category: category, isFocused: $focusedCategoryID)
                }
            } header: {
                Text("MONTHLY BUDGET · EXPENSE CATEGORIES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.textDim)
            } footer: {
                HStack {
                    Text("Total budgeted")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.textDim)
                    Spacer()
                    Text(totalBudgeted.formatted(.currency(code: "EUR")))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.textPrimary)
                }
            }
            .appFormSectionBackground()
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Budgets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if focusedCategoryID != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedCategoryID = nil }
                }
            }
        }
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    return NavigationStack { BudgetsView() }
        .modelContainer(container)
        .environment(DataChangedSignal())
        .preferredColorScheme(.dark)
}
