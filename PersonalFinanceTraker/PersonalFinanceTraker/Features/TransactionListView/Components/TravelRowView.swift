//
//  TravelRowView.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// A collapsed travel inside an Activity day section. Deliberately shaped like
/// `TransactionItemView` — same leading tile, same trailing signed amount — so the
/// list reads as one thing. The chevron is what separates it: this row opens a
/// sheet rather than the edit form, and shape alone (not colour) says so.
struct TravelRowView: View {
    let travel: TravelSummary

    @AppStorage("app_base_currency") private var currencyCode = "EUR"

    private var countLabel: String { TravelCountLabel.text(travel.count) }

    /// "5 expenses · 12–16 Sep". The row sits in the day section of its *latest* member,
    /// so without the span a trip that ran all week looks like it happened today.
    /// A single-day trip says only the count — the section header already gives the day.
    private var subtitle: String {
        guard let start = travel.startDate, let end = travel.endDate else { return countLabel }
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        let from = start.formatted(style)
        let to = end.formatted(style)
        return from == to ? countLabel : "\(countLabel) · \(from) – \(to)"
    }

    var body: some View {
        HStack(spacing: 12) {
            GlassCard(tint: Color.accentIndigo.opacity(0.12), borderRadius: 12) {
                Image(systemName: travel.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentIndigo)
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(travel.name)
                    .font(.body)
                    .foregroundStyle(.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }

            Spacer(minLength: 8)

            // Always-signed, matching TransactionItemView: direction never depends on
            // colour alone. A trip can net positive if a refund outweighs its expenses.
            // An empty travel is neither income nor spending, so it gets neither the
            // "+" nor the green — a brand new folder reading "+0,00 €" looks like a gain.
            Text(
                travel.total,
                format: .currency(code: currencyCode)
                    .sign(strategy: travel.total == 0 ? .never : .always())
            )
            .font(.headline)
            .foregroundStyle(travel.total == 0 ? Color.textMid : (travel.total > 0 ? .positive : .negative))
            .privacyBlur()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.textDim)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(travel.name), \(subtitle)")
        .accessibilityHint("Shows the expenses in this travel")
    }
}

#Preview {
    NavigationStack {
        List {
            TravelRowView(travel: TravelSummary(
                id: UUID(), name: "Barcellona Travel", symbolName: "airplane",
                total: -400, count: 6, anchorDate: Date(),
                startDate: Date().addingTimeInterval(-4 * 86_400), endDate: Date()
            ))
            TravelRowView(travel: TravelSummary(
                id: UUID(), name: "Weekend in the mountains with friends", symbolName: "mountain.2",
                total: -1234.56, count: 1, anchorDate: Date()
            ))
            TravelRowView(travel: TravelSummary(
                id: UUID(), name: "Not started yet", symbolName: "backpack",
                total: 0, count: 0, anchorDate: Date()
            ))
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg0)
    }
}
