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

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Safe to Spend")
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

                if let safe = viewModel.safeToSpend {
                    if safe.income == 0 {
                        Text("Add your income to see what's safe to spend until payday.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        hero(safe)
                        Divider().opacity(0.15)
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

    private func hero(_ safe: SafeToSpend) -> some View {
        let payday = safe.payday.formatted(.dateTime.day().month(.abbreviated))
        let perDay = SafeToSpendSnapshot.perDay(safe.amount, from: viewModel.currentDate(), until: safe.payday)
        return VStack(alignment: .leading, spacing: 4) {
            // Fixed-width mask when hidden — a plain blur would still leak the
            // amount's digit count (and thus rough magnitude) via glyph width.
            Text(masked(safe.amount))
                .font(.largeTitle.bold())
                .foregroundStyle(safe.amount < 0 ? Color.negative : Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
                .privacyBlur(radius: 8)

            Group {
                if safe.amount < 0 {
                    Text("Over plan until \(payday)")
                } else if let perDay {
                    // Whole euros, same as the widget: "€26/day".
                    Text("until \(payday) · \(appSettings.hideAmounts ? "••••" : perDay.formatted(.currency(code: CurrencyService().baseCurrency).precision(.fractionLength(0))))/day")
                } else {
                    Text("until \(payday)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(safe.amount < 0 ? Color.negative : Color.textMid)
        }
        .accessibilityElement(children: .combine)
    }

    private func breakdown(_ safe: SafeToSpend) -> some View {
        DisclosureGroup {
            VStack(spacing: 6) {
                row("Income this cycle", safe.income, sign: "+")
                row("Spent so far", safe.spent)
                if safe.recurring > 0 { row("Recurring still due", safe.recurring) }
                if safe.goals > 0 { row("Goal contributions", safe.goals) }
                row("Safety buffer (\(appSettings.safeToSpendBufferPercent)%)", safe.buffer)
            }
            .padding(.top, 8)
        } label: {
            Text("How it's calculated")
                .font(.subheadline)
                .foregroundStyle(.textMid)
        }
        .tint(.textMid)
    }

    private func row(_ label: LocalizedStringKey, _ amount: Decimal, sign: String = "−") -> some View {
        LabeledContent {
            Text(appSettings.hideAmounts ? "••••" : "\(sign)\(amount.formattedEUR())")
                .monospacedDigit()
                .privacyBlur()
        } label: {
            Text(label)
        }
        .font(.subheadline)
        .foregroundStyle(.textMid)
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
