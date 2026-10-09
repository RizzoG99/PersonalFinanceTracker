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
                VStack(spacing: 16) {
                    ForecastCard(summary: summary)
                    if !summary.categories.isEmpty {
                        CycleCategoriesCard(summary: summary)
                    }
                }
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
        // Full height: at .medium the category list sat below the fold, easy to never find.
        .presentationDetents([.large])
        .presentationBackground { AppBackground() }
    }
}

struct ForecastCard: View {
    let summary: CycleSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Side by side normally; stacked at accessibility sizes, where pairs no longer fit a row.
    private func row(spacing: CGFloat = 4) -> AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .top))
    }

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
        let header = row(), dates = row(spacing: 0)
        GlassCard(borderRadius: 14) {
            VStack(alignment: .leading, spacing: 14) {
                header {
                    Label("At this pace", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.bold())
                        .foregroundStyle(.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(daysLeft) days left")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }

                if !actualPoints.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        chart
                        // The x-axis is hidden; these say where the cycle starts and ends.
                        dates {
                            Text(summary.cycleStart, format: .dateTime.day().month(.abbreviated))
                            Spacer(minLength: 0)
                            Text("Payday \(summary.payday.formatted(.dateTime.day().month(.abbreviated)))")
                        }
                        .font(.caption)
                        .foregroundStyle(.textDim)
                    }
                }

                Divider().overlay { Color.hairline }

                if hasUsual {
                    summaryRow
                } else {
                    // The chart is hidden from VoiceOver, so its one number has to be said here.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.spentSoFar.formattedEUR())
                            .font(.title2.bold())
                            .foregroundStyle(.textPrimary)
                            .privacyBlur()
                        Text("spent so far this cycle")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text("Not enough history for a forecast yet")
                            .font(.subheadline)
                            .foregroundStyle(.textMid)
                            .padding(.top, 4)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            // Stacked rows (accessibility sizes) have no Spacer pushing them wide, so the
            // card would hug its text and float centred.
            .frame(maxWidth: .infinity, alignment: .leading)
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

            if let today = actualPoints.last {
                PointMark(x: .value("Day", today.day), y: .value("Spend", today.amount))
                    .foregroundStyle(trendColor)
                    .symbolSize(50)
                    // Below the point: above it, near the usual line, it ran into "usual total".
                    .annotation(position: .bottom, spacing: 4) {
                        Text("today")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                    }
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
                    // Top-leading: at the trailing end the projection converges on the rule and
                    // would run through it; below, the "today" label sits.
                    .annotation(position: .top, alignment: .leading) {
                        Text("usual total")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                    }
            }
        }
        .frame(height: 180)
        // In-plot labels can't reflow, so they stop growing here; the chart is hidden from
        // VoiceOver and every figure it carries is repeated as full-size text below.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .chartXScale(domain: 1...max(cycleDays, 2))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .privacyBlur()
        // The numbers below say the same; VoiceOver reads those instead of the plot.
        .accessibilityHidden(true)
    }

    private var summaryRow: some View {
        let diff = summary.projected - summary.usualFullCycle
        let layout = row(spacing: 10)
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.projected.formattedEUR())
                    .font(.title2.bold())
                    .foregroundStyle(.textPrimary)
                    .privacyBlur()
                Text("expected spending by payday")
                    .font(.caption)
                    .foregroundStyle(.textDim)
                // The verdict's own comparison, so "in line" / "+X" has a number behind it.
                Text("Usually \(summary.usualFullCycle.formattedEUR()) by payday, \(summary.usualSoFar.formattedEUR()) by today")
                    .font(.caption)
                    .foregroundStyle(.textMid)
                    .padding(.top, 6)
                    .privacyBlur()
            }
            Spacer(minLength: 0)
            if diff == 0 {
                Text("in line with usual")
                    .font(.caption.bold())
                    .foregroundStyle(.textMid)
            } else {
                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                    // Red only with a "faster" verdict: a few % over while on track isn't a warning.
                    Text(diff > 0 ? "+\(diff.formattedEUR())" : "-\(abs(diff).formattedEUR())")
                        .font(.caption.bold())
                        .foregroundStyle(summary.pace == .faster ? Color.negative : Color.textMid)
                        .privacyBlur()
                    Text("vs usual")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Where this cycle's spending went, per category, against the usual at the same point.
struct CycleCategoriesCard: View {
    let summary: CycleSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GlassCard(borderRadius: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Where it's going")
                    .font(.subheadline.bold())
                    .foregroundStyle(.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(summary.categories, id: \.category) { row in
                    let stacked = dynamicTypeSize.isAccessibilitySize
                    let layout = stacked
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                    layout {
                        Text(row.category)
                            .font(.subheadline)
                            .foregroundStyle(.textPrimary)
                        Spacer(minLength: 0)
                        VStack(alignment: stacked ? .leading : .trailing, spacing: 2) {
                            Text(row.spent.formattedEUR())
                                .font(.subheadline.bold())
                                .foregroundStyle(.textPrimary)
                                .monospacedDigit()
                                .privacyBlur()
                            if summary.pace != .building {
                                delta(row.delta)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            // Stacked rows (accessibility sizes) have no Spacer pushing them wide, so the
            // card would hug its text and float centred.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Red only for increases while the verdict is "faster", same rule as the forecast delta.
    private func delta(_ value: Decimal) -> some View {
        Group {
            // Separate literals: a ternary would make these plain Strings, which Text never localizes.
            if value == 0 {
                Text("as usual")
            } else if value > 0 {
                Text("+\(value.formattedEUR()) vs usual").privacyBlur()
            } else {
                Text("-\(abs(value).formattedEUR()) vs usual").privacyBlur()
            }
        }
        .font(.caption)
        .foregroundStyle(value > 0 && summary.pace == .faster ? Color.negative : Color.textDim)
    }
}
