//
//  BalanceCardView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct BalanceCardView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Total Balance")
                        .font(.subheadline)
                        .foregroundStyle(.textMid)

                    Spacer()

                    Button {
                        appSettings.toggleHideAmounts()
                    } label: {
                        Image(systemName: appSettings.hideAmounts ? "eye.slash" : "eye")
                            .foregroundStyle(.textMid)
                    }
                    .accessibilityLabel(appSettings.hideAmounts ? String(localized: "Show amounts") : String(localized: "Hide amounts"))
                }

                // Fixed-width mask when hidden — a plain blur would still leak the
                // balance's digit count (and thus its rough magnitude) via glyph width.
                Text(appSettings.hideAmounts ? "••••••" : viewModel.totalBalance.formattedEUR())
                    .font(.largeTitle.bold())
                    .foregroundStyle(.textPrimary)
                    .privacyBlur(radius: 8)

                Divider().opacity(0.15)

                Text(viewModel.financialMonthLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.monthlyIncome == 0 && viewModel.monthlyExpenses == 0 {
                    Text("No transactions yet this period")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        StatCard(icon: "arrow.down.left",
                                 label: "Income",
                                 value: "+\(viewModel.monthlyIncome.formattedEUR())",
                                 color: .positive)

                        StatCard(icon: "arrow.up.right",
                                 label: "Expenses",
                                 value: "-\(viewModel.monthlyExpenses.formattedEUR())",
                                 color: .negative)
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
    let repo = TransactionActor.make(container)
    let dashVM = DashboardViewModel(repo: repo)
    return BalanceCardView()
        .environment(dashVM)
        .environment(AppSettings())
        .modelContainer(container)
}
