//
//  ForecastCard.swift
//  PersonalFinanceTraker
//

import SwiftUI
import Charts

/// The month card's detail (#191): spending so far this cycle, where it's heading, and the usual.
struct CycleForecastSheet: View {
    let summary: CycleSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ForecastCard(summary: summary)
                    .padding(16)
                    .readableWidth()
            }
            .navigationTitle("This cycle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground { AppBackground() }
    }
}

struct ForecastCard: View {
    let summary: CycleSummary

    private struct ChartPoint: Identifiable {
        var id: Int { day }
        let day: Int
        let amount: Double
    }

    /// Without earlier cycles there's no "usual" to project from — show only what happened.
    private var hasUsual: Bool { summary.pace != .building }
    /// Neutral while there's no verdict yet — green would read as "fine" before anything was judged.
    private var trendColor: Color {
        switch summary.pace {
        case .building: .textMid
        case .onTrack: .positive
        case .faster: .negative
        }
    }

    private var cycleDays: Int {
        Calendar.current.dateComponents([.day], from: summary.cycleStart, to: summary.payday).day ?? 30
    }

    private var daysLeft: Int {
        SafeToSpendSnapshot.daysLeft(from: .now, until: summary.payday, calendar: .current)
    }

    private var actualPoints: [ChartPoint] {
        summary.dailyCumulative.enumerated().map {
            ChartPoint(day: $0.offset + 1, amount: Double(truncating: $0.element as NSDecimalNumber))
        }
    }

    // Two-point segment: last actual → projected cycle end
    private var projectionPoints: [ChartPoint] {
        guard hasUsual, let last = actualPoints.last else { return [] }
        return [last, ChartPoint(day: cycleDays, amount: Double(truncating: summary.projected as NSDecimalNumber))]
    }

    var body: some View {
        GlassCard(borderRadius: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("At this pace", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.bold())
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Text("\(daysLeft) days left")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }

                if !actualPoints.isEmpty {
                    chart
                }

                Divider().overlay { Color.hairline }

                if hasUsual {
                    summaryRow
                } else {
                    Text("Not enough history for a forecast yet")
                        .font(.subheadline)
                        .foregroundStyle(.textMid)
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(actualPoints) { point in
                AreaMark(x: .value("Day", point.day), y: .value("Spend", point.amount))
                    .foregroundStyle(trendColor.opacity(0.2))
                LineMark(
                    x: .value("Day", point.day),
                    y: .value("Spend", point.amount),
                    series: .value("Series", "actual")
                )
                .foregroundStyle(trendColor)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Dashed projection segment (last actual → cycle end)
            ForEach(projectionPoints) { point in
                LineMark(
                    x: .value("Day", point.day),
                    y: .value("Spend", point.amount),
                    series: .value("Series", "projection")
                )
                .foregroundStyle(trendColor.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }

            if hasUsual {
                RuleMark(y: .value("Usual", Double(truncating: summary.usualFullCycle as NSDecimalNumber)))
                    .foregroundStyle(.textDim.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    // Below the rule: above it, a faster projection's dashed line runs through the label.
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("usual total")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                    }
            }
        }
        .frame(height: 120)
        .chartXScale(domain: 1...max(cycleDays, 2))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .privacyBlur()
        // The numbers below say the same; VoiceOver reads those instead of the plot.
        .accessibilityHidden(true)
    }

    private var summaryRow: some View {
        let diff = summary.projected - summary.usualFullCycle
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.projected.formattedEUR())
                    .font(.title2.bold())
                    .foregroundStyle(.textPrimary)
                    .privacyBlur()
                Text("projected this cycle")
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
            Spacer()
            if diff == 0 {
                Text("in line with usual")
                    .font(.caption.bold())
                    .foregroundStyle(.textMid)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    // Red only with a "faster" verdict: a few % over while on track isn't a warning.
                    Text(diff > 0 ? "+\(diff.formattedEUR())" : "-\(abs(diff).formattedEUR())")
                        .font(.caption.bold())
                        .foregroundStyle(summary.pace == .faster ? Color.negative : Color.textMid)
                        .privacyBlur()
                    Text("vs usual \(summary.usualFullCycle.formattedEUR())")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                        .privacyBlur()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
