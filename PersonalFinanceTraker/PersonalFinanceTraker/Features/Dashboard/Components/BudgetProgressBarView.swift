//  BudgetProgressBarView.swift
//  PersonalFinanceTraker

import SwiftUI
import SwiftData

struct BudgetProgressBarView: View {
    let progress: BudgetProgress
    var onTap: (() -> Void)?
    @Environment(AppSettings.self) private var appSettings: AppSettings?

    private var hideAmounts: Bool { appSettings?.hideAmounts ?? false }

    private var barColor: Color {
        if progress.isOverBudget { return .negative }
        if progress.isNearLimit { return .categoryAmber }
        return Color(categoryToken: progress.colorToken)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: progress.systemImage)
                        .foregroundStyle(Color(categoryToken: progress.colorToken))
                    Text(progress.categoryName.removingLeadingEmoji.localizedCategoryDisplay)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Text("\(progress.spent.formatted(.currency(code: "EUR"))) / \(progress.budget.formatted(.currency(code: "EUR")))")
                        .font(.caption)
                        .foregroundStyle(progress.isOverBudget ? .negative : .textDim)
                        .privacyBlur()
                }
                ProgressView(value: min(progress.percent, 1.0))
                    .tint(barColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityFullLabel)
        .accessibilityAddTraits(.isButton)
    }

    // ponytail: built from pre-localized fragments (not one raw ternary/interpolation) so the
    // category name, amounts, and each status phrase all go through the catalog independently.
    private var accessibilityFullLabel: String {
        let name = progress.categoryName.removingLeadingEmoji.localizedCategoryDisplay
        if hideAmounts {
            return String(localized: "\(name), amount hidden")
        }
        let spent = progress.spent.formatted(.currency(code: "EUR"))
        let budget = progress.budget.formatted(.currency(code: "EUR"))
        let status = progress.isOverBudget
            ? String(localized: ", over budget")
            : String(localized: ", near budget limit")
        return String(localized: "\(name), \(spent) of \(budget)") + status
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let category = CategoryModel(name: "Groceries", systemImage: "cart.fill", type: .expense, colorToken: "categoryGreen", monthlyBudget: 300)
    container.mainContext.insert(category)

    return VStack(spacing: 16) {
        BudgetProgressBarView(
            progress: BudgetProgress(
                id: category.persistentModelID,
                categoryName: "Groceries", systemImage: "cart.fill", colorToken: "categoryGreen",
                budget: 300, spent: 270
            )
        )
        BudgetProgressBarView(
            progress: BudgetProgress(
                id: category.persistentModelID,
                categoryName: "Takeout", systemImage: "bag.fill", colorToken: "categoryOrange",
                budget: 200, spent: 276
            )
        )
    }
    .padding()
    .appBackground()
    .preferredColorScheme(.dark)
}
