//  BudgetsView.swift
//  PersonalFinanceTraker

import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Query(sort: \CategoryModel.name) private var categories: [CategoryModel]

    private var expenseCategories: [CategoryModel] {
        categories.filter { $0.transactionType == .expense }
    }

    var body: some View {
        List {
            Section {
                ForEach(expenseCategories) { category in
                    BudgetRow(category: category)
                }
            } header: {
                Text("EXPENSE CATEGORIES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.textDim)
            }
            .appFormSectionBackground()
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Budgets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    return NavigationStack { BudgetsView() }
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
