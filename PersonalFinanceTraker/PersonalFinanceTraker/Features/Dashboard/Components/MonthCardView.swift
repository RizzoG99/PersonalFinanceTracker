//
//  MonthCardView.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// Home's month card (#191): "How am I doing this cycle?" — in / out / saved, a pace verdict
/// and one forecast sentence. Tap opens the forecast detail.
struct MonthCardView: View {
    let summary: CycleSummary
    /// iPad: opens the forecast in the shell's shared inspector. Nil on iPhone — own sheet.
    var onShowForecast: (() -> Void)? = nil
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingForecast = false

    var body: some View {
        Button { if let onShowForecast { onShowForecast() } else { showingForecast = true } } label: {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("This cycle")
                            .font(.subheadline)
                            .foregroundStyle(.textMid)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if !dynamicTypeSize.isAccessibilitySize { paceLabel }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.textDim)
                            .accessibilityHidden(true)
                    }
                    // Long Italian verdicts ("Stiamo costruendo il quadro") would squeeze the title.
                    if dynamicTypeSize.isAccessibilitySize { paceLabel }

                    amounts

                    if let sentence = forecastSentence {
                        Text(sentence)
                            .font(.subheadline)
                            .foregroundStyle(.textMid)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // .plain only hit-tests drawn pixels; without this the gaps between texts ignore taps.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the forecast for this cycle")
        .sheet(isPresented: $showingForecast) {
            CycleForecastSheet(summary: summary)
        }
    }

    // MARK: - Pieces

    private var paceLabel: some View {
        let (title, icon, color): (LocalizedStringKey, String, Color) = switch summary.pace {
        case .building: ("Building your picture", "hourglass", .textDim)
        case .onTrack: ("On track", "checkmark.circle.fill", .positive)
        case .faster: ("Faster than usual", "arrow.up.right.circle.fill", .negative)
        }
        return Label(title, systemImage: icon)
            .font(.subheadline.bold())
            .foregroundStyle(color)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
    }

    /// Zero income: only Out — the hero above already explains the missing salary.
    private var amounts: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            if summary.income > 0 {
                amount("In", summary.income, color: .textPrimary)
            }
            amount("Out", summary.out, color: .textPrimary)
            if summary.income > 0 {
                amount("Saved", summary.saved, color: summary.saved < 0 ? .negative : .positive)
            }
        }
    }

    private func amount(_ label: LocalizedStringKey, _ value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.textDim)
            Text(verbatim: appSettings.hideAmounts ? "••••" : value.formattedEUR())
                .font(.headline)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacyBlur()
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Same basis as the verdict (`projected`), so the two never disagree.
    private var forecastSentence: String? {
        guard summary.pace != .building else { return nil }
        let diff = summary.projected - summary.usualFullCycle
        let amount = appSettings.hideAmounts ? "••••" : abs(diff).formattedEURCompact()
        var sentence = diff > 0
            ? String(localized: "At this pace you'll end the cycle about \(amount) above usual.")
            : diff < 0
                ? String(localized: "At this pace you'll end the cycle about \(amount) below usual.")
                : String(localized: "At this pace you'll end the cycle in line with usual.")
        let drivers = summary.drivers.map { driver in
            let delta = appSettings.hideAmounts ? "••••" : driver.delta.formattedEURCompact()
            return "\(driver.category) (+\(delta))"
        }
        if drivers.count == 2 {
            sentence += " " + String(localized: "Mostly \(drivers[0]) and \(drivers[1]).")
        } else if let only = drivers.first {
            sentence += " " + String(localized: "Mostly \(only).")
        }
        return sentence
    }
}

#Preview {
    let summary = CycleSummary(
        income: 2_000, out: 1_420, spentSoFar: 1_420, pace: .faster,
        usualSoFar: 1_200, usualFullCycle: 1_600,
        categories: [
            .init(category: "🍽️ Restaurants", spent: 300, delta: 90),
            .init(category: "🛒 Groceries", spent: 240, delta: 0),
            .init(category: "🚗 Transport", spent: 120, delta: 40),
        ],
        dailyCumulative: [120, 300, 300, 520, 700, 820, 900, 1_000, 1_180, 1_300, 1_420],
        cycleStart: Calendar.current.date(byAdding: .day, value: -10, to: .now)!,
        payday: Calendar.current.date(byAdding: .day, value: 20, to: .now)!
    )
    return MonthCardView(summary: summary)
        .padding(16)
        .environment(AppSettings())
}
