//
//  UpcomingPreviewCard.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

/// Home's compact preview of the financial calendar (#189): the next 7 days of recurring money.
/// The full 14-day timeline lives in Plan.
struct UpcomingPreviewCard: View {
    let charges: [UpcomingCharge]
    /// Opens Plan (iPhone) or the Recurring sidebar destination (iPad).
    var onSeeAll: (() -> Void)? = nil

    private static let rowLimit = 3

    var body: some View {
        let outflow = UpcomingCharge.totals(charges).outflow
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next 7 days")
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Out \(outflow.formattedEUR())")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                        .privacyBlur()
                }
                Spacer()
                if let onSeeAll {
                    Button("See all", action: onSeeAll)
                        .font(.subheadline.bold())
                        .tint(.accentIndigo)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 4)
            GlassCard {
                VStack(spacing: 8) {
                    ForEach(charges.prefix(Self.rowLimit)) { charge in
                        UpcomingChargeRow(charge: charge, showsDay: true)
                        if charge.id != charges.prefix(Self.rowLimit).last?.id {
                            Divider()
                                .padding(.horizontal, -16)
                        }
                    }
                    if charges.count > Self.rowLimit {
                        Text("+\(charges.count - Self.rowLimit) more")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self, RecurrenceRule.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let rules = [
        RecurrenceRule(frequency: .weekly, interval: 1, startDate: .now.addingTimeInterval(3_600), amount: -17.99, note: "Netflix", category: "Streaming Services", currencyCode: "EUR"),
        RecurrenceRule(frequency: .monthly, interval: 1, startDate: .now.addingTimeInterval(86_400 * 2), amount: 2_100, note: "Salary", category: "Salary", currencyCode: "EUR"),
        RecurrenceRule(frequency: .monthly, interval: 1, startDate: .now.addingTimeInterval(86_400 * 4), autoRecord: false, amount: -240, note: "Motorbike loan", category: "Transport", currencyCode: "EUR"),
        RecurrenceRule(frequency: .monthly, interval: 1, startDate: .now.addingTimeInterval(86_400 * 5), amount: -50, note: "", category: "→ Trip", currencyCode: "EUR"),
    ]
    rules.forEach(container.mainContext.insert)
    return UpcomingPreviewCard(charges: UpcomingCharge.timeline(rules: rules.map(RecurrenceRuleSnapshot.init), days: 7)) {}
        .padding(16)
        .appBackground()
}
