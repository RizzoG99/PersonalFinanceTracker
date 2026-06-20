//
//  SavingsGoalCardView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct SavingsGoalCardView: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Savings Goal")
                        .font(.subheadline)
                        .foregroundStyle(.textMid)
                    Spacer()
                    Text("\(Int(viewModel.savingsGoalProgress * 100))%")
                        .font(.headline)
                        .foregroundStyle(.accentIndigo)
                }

                ProgressView(value: min(viewModel.savingsGoalProgress, 1.0))
                    .tint(.accentIndigo)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text(formatEUR(viewModel.currentSavings))
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Goal")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text(formatEUR(viewModel.savingsGoal))
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                    }
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
    let repo = TransactionRepository(context: container.mainContext)
    let dashVM = DashboardViewModel(repo: repo)
    return SavingsGoalCardView()
        .environment(dashVM)
        .modelContainer(container)
}
