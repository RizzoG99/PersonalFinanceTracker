//  BudgetProgressBarView.swift
//  PersonalFinanceTraker

import SwiftUI
import SwiftData

struct BudgetProgressBarView: View {
    let progress: BudgetProgress

    private var barColor: Color {
        progress.isOverBudget ? .negative : Color(categoryToken: progress.colorToken)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: progress.systemImage)
                    .foregroundStyle(Color(categoryToken: progress.colorToken))
                Text(progress.categoryName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("\(progress.spent.formatted(.currency(code: "EUR"))) / \(progress.budget.formatted(.currency(code: "EUR")))")
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
            ProgressView(value: min(progress.percent, 1.0))
                .tint(barColor)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.bg1)
        )
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let category = CategoryModel(name: "Groceries", systemImage: "cart.fill", type: .expense, colorToken: "categoryGreen", monthlyBudget: 300)
    container.mainContext.insert(category)

    return BudgetProgressBarView(
        progress: BudgetProgress(
            id: category.persistentModelID,
            categoryName: "Groceries", systemImage: "cart.fill", colorToken: "categoryGreen",
            budget: 300, spent: 270
        )
    )
    .padding()
    .appBackground()
    .preferredColorScheme(.dark)
}
