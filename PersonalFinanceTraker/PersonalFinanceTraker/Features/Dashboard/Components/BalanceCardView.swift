//
//  BalanceCardView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

/// Home's hero (#190): what's safe to spend until payday, and how it was worked out.
struct BalanceCardView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Safe to Spend")
                        .font(.subheadline)
                        .foregroundStyle(.textMid)
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    Button {
                        appSettings.toggleHideAmounts()
                    } label: {
                        Image(systemName: appSettings.hideAmounts ? "eye.slash" : "eye")
                            .foregroundStyle(.textMid)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(appSettings.hideAmounts ? String(localized: "Show amounts") : String(localized: "Hide amounts"))
                }
                .padding(.vertical, -12) // the 44pt eye target shouldn't grow the header

                if let safe = viewModel.safeToSpend {
                    if safe.income == 0 {
                        noIncome(safe)
                    } else {
                        hero(safe)
                        breakdown(safe)
                    }
                } else {
                    Text(verbatim: "€000.00")
                        .font(.largeTitle.bold())
                        .redacted(reason: .placeholder)
                }
            }
        }
    }

    /// No income this cycle. With spending already recorded the usual cause is a pay cycle that
    /// doesn't start on salary day — say so instead of looking like an empty app.
    @ViewBuilder
    private func noIncome(_ safe: SafeToSpend) -> some View {
        let start = safe.cycleStart.formatted(.dateTime.day().month(.abbreviated))
        if safe.spent > 0 {
            row("Spent so far", safe.spent, sign: "-")
            Text("No income recorded since \(start). If your salary arrives on another day, set it as the pay cycle start in Settings.")
                .font(.subheadline)
                .foregroundStyle(.textMid)
        } else if !viewModel.hasNoTransactions {
            // Older history only (e.g. an imported statement): Recent Transactions shows it
            // right below, so "add your income" alone would read as the app ignoring it.
            Text("No transactions since \(start). Add this period's income to see what you can spend.")
                .font(.subheadline)
                .foregroundStyle(.textMid)
        } else {
            Text("Add your income to see what's safe to spend until payday.")
                .font(.subheadline)
                .foregroundStyle(.textMid)
        }
    }

    private func hero(_ safe: SafeToSpend) -> some View {
        let lastDay = SafeToSpendSnapshot.lastDay(before: safe.payday).formatted(.dateTime.day().month(.abbreviated))
        let perDay = SafeToSpendSnapshot.perDay(safe.amount, from: viewModel.currentDate(), until: safe.payday)
            .map { appSettings.hideAmounts ? "••••" : $0.formatted(.currency(code: CurrencyService().baseCurrency).precision(.fractionLength(0))) }
        return VStack(alignment: .leading, spacing: 4) {
            // Fixed-width mask when hidden — a plain blur would still leak the
            // amount's digit count (and thus rough magnitude) via glyph width.
            Text(masked(safe.amount))
                .font(.largeTitle.bold())
                .foregroundStyle(safe.amount < 0 ? Color.negative : Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(truncating: safe.amount as NSDecimalNumber)))
                .animation(.default, value: safe.amount)
                .privacyBlur(radius: 8)

            Group {
                if safe.amount < 0 {
                    Text("Over plan until \(lastDay)")
                } else if let perDay {
                    Text("until \(lastDay) · \(perDay)/day")
                        .accessibilityLabel(Text("until \(lastDay), \(perDay) per day"))
                } else {
                    Text("until \(lastDay)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(safe.amount < 0 ? Color.negative : Color.textMid)
        }
        .accessibilityElement(children: .combine)
    }

    private func breakdown(_ safe: SafeToSpend) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                row("Income this cycle", safe.income, sign: "+")
                row("Spent so far", safe.spent)
                if safe.recurring > 0 { row("Recurring still due", safe.recurring) }
                if safe.goals > 0 { row("Goal contributions", safe.goals) }
                row("Safety buffer (\(appSettings.safeToSpendBufferPercent)%)", safe.buffer)
                Text("Safe to Spend keeps this share of your income aside for the unexpected.")
                    .font(.caption)
                    .foregroundStyle(.textDim)
                Divider()
                row("Safe to Spend", safe.amount, sign: "", emphasized: true)
            }
            .padding(.top, 8)
        } label: {
            Text("How it's calculated")
                .font(.subheadline)
                .foregroundStyle(.textMid)
        }
        .tint(.textMid)
    }

    /// Label and amount side by side; stacked at accessibility sizes so long Italian labels fit.
    private func row(_ label: LocalizedStringKey, _ amount: Decimal, sign: String = "-", emphasized: Bool = false) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout())
        return layout {
            Text(label)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Text(verbatim: appSettings.hideAmounts ? "••••" : "\(sign)\(amount.formattedEUR())")
                .monospacedDigit()
                .privacyBlur()
        }
        .font(.subheadline.weight(emphasized ? .semibold : .regular))
        .foregroundStyle(emphasized ? Color.textPrimary : Color.textMid)
        .accessibilityElement(children: .combine)
    }

    private func masked(_ amount: Decimal) -> String {
        appSettings.hideAmounts ? "••••••" : amount.formattedEUR()
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let repo = TransactionActor.make(container)
    let dashVM = DashboardViewModel(repo: repo)
    dashVM.load()
    return BalanceCardView()
        .padding(16)
        .environment(dashVM)
        .environment(AppSettings())
        .modelContainer(container)
}
