//
//  UpcomingChargeRow.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// One financial-calendar row: Plan's timeline (grouped under a day header) and Home's preview.
struct UpcomingChargeRow: View {
    let charge: UpcomingCharge
    /// Home's flat preview has no day headers, so the row carries its own day.
    var showsDay = false

    private var title: String { charge.rule.title }

    var body: some View {
        ChargeRowLayout(
            category: charge.rule.category, title: Text(title),
            amount: charge.rule.amount, currencyCode: charge.rule.currencyCode
        ) {
            if showsDay {
                Text(Self.dayLabel(for: charge.date))
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
        }
        // The whole row is the tap target, not just its text — a Spacer isn't hit-testable.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Day-based, not `.relative`: a charge due later today would otherwise read "in 10 hours".
    static func dayLabel(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return switch days {
        case 0: String(localized: "Today · \(day)")
        case 1: String(localized: "Tomorrow · \(day)")
        default: day
        }
    }
}

/// Category tile, title over a subtitle, signed amount on the trailing side: the row shared by
/// the timeline and the fixed-expense cards (#206), so a charge looks the same in both. At
/// accessibility sizes the amount moves under the title instead of squeezing it into a sliver.
struct ChargeRowLayout<Subtitle: View>: View {
    let category: String
    let title: Text
    let amount: Decimal
    let currencyCode: String
    /// A median of varying bills: shown as "≈", read as "about … varies".
    var approximate = false
    @ViewBuilder let subtitle: Subtitle

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let info = CategoryInfo.info(for: category)
        HStack(alignment: stacked ? .top : .center, spacing: 12) {
            // Same tile as Recent Transactions' rows.
            GlassCard(tint: info.color.opacity(0.12), borderRadius: 12) {
                Image(systemName: info.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(info.color)
                    .frame(width: 16, height: 16)
            }
            .accessibilityHidden(true)
            // AnyLayout keeps the title and amount's identity when the text size crosses over.
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.body)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(stacked ? nil : 2)
                    subtitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                amountText
            }
        }
    }

    /// Signed, income in green: money in and out share one timeline.
    private var amountText: some View {
        let formatted = amount.formatted(.currency(code: currencyCode).sign(strategy: .always()))
        return (approximate ? Text("≈ \(formatted)") : Text(verbatim: formatted))
            .font(.headline)
            .foregroundStyle(amount >= 0 ? .positive : .textPrimary)
            .accessibilityLabel(approximate ? Text("About \(formatted), varies") : Text(verbatim: formatted))
            .privacyBlur()
    }
}
