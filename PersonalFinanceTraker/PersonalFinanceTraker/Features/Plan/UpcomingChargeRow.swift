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

    private var title: String {
        charge.rule.note.isEmpty
            ? charge.rule.category.removingLeadingEmoji.localizedCategoryDisplay
            : charge.rule.note
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: CategoryInfo.info(for: charge.rule.category).symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CategoryInfo.info(for: charge.rule.category).color)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(2)
                if showsDay {
                    Text(Self.dayLabel(for: charge.date))
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
            }
            Spacer()
            // Signed, income in green: money in and out now share one timeline.
            Text(charge.rule.amount, format: .currency(code: charge.rule.currencyCode).sign(strategy: .always()))
                .font(.headline)
                .foregroundStyle(charge.rule.amount >= 0 ? .positive : .textPrimary)
                .privacyBlur()
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
