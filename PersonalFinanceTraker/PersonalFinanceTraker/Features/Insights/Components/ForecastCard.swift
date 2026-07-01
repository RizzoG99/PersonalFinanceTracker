//
//  ForecastCard.swift
//  PersonalFinanceTraker
//

import SwiftUI
import Charts

struct ForecastCard: View {
    let forecast: SpendingForecast

    private struct ChartPoint: Identifiable {
        var id: Int { day }
        let day: Int
        let amount: Double
    }

    private var isOverPace: Bool {
        forecast.lastThreeMonthAvg > 0 && forecast.projectedAmount > forecast.lastThreeMonthAvg
    }
    private var trendColor: Color { isOverPace ? .negative : .positive }

    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: .now)?.count ?? 30
    }

    private var actualPoints: [ChartPoint] {
        forecast.dailyActuals.map {
            ChartPoint(day: $0.day, amount: NSDecimalNumber(decimal: $0.cumulative).doubleValue)
        }
    }

    // Two-point segment: last actual → projected month-end
    private var projectionPoints: [ChartPoint] {
        guard let last = actualPoints.last else { return [] }
        return [
            last,
            ChartPoint(
                day: daysInMonth,
                amount: NSDecimalNumber(decimal: forecast.projectedAmount).doubleValue
            ),
        ]
    }

    var body: some View {
        GlassCard(borderRadius: 14) {
            VStack(alignment: .leading, spacing: 14) {
                // Header row
                HStack {
                    Label("At this pace", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.bold())
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Text("\(forecast.daysLeft) days left")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }

                // Chart (only rendered when we have data)
                if !actualPoints.isEmpty {
                    Chart {
                        // Solid area + line for actual days
                        ForEach(actualPoints) { point in
                            AreaMark(
                                x: .value("Day", point.day),
                                y: .value("Spend", point.amount)
                            )
                            .foregroundStyle(trendColor.opacity(0.2))
                            LineMark(
                                x: .value("Day", point.day),
                                y: .value("Spend", point.amount),
                                series: .value("Series", "actual")
                            )
                            .foregroundStyle(trendColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }

                        // Dashed projection segment (last actual → month-end)
                        ForEach(projectionPoints) { point in
                            LineMark(
                                x: .value("Day", point.day),
                                y: .value("Spend", point.amount),
                                series: .value("Series", "projection")
                            )
                            .foregroundStyle(trendColor.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        }

                        // 3-month average reference line
                        if forecast.lastThreeMonthAvg > 0 {
                            let avg = NSDecimalNumber(decimal: forecast.lastThreeMonthAvg).doubleValue
                            RuleMark(y: .value("Avg", avg))
                                .foregroundStyle(.textDim.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .annotation(position: .top, alignment: .trailing) {
                                    Text("avg")
                                        .font(.caption2)
                                        .foregroundStyle(.textDim)
                                }
                        }
                    }
                    .frame(height: 90)
                    .chartXScale(domain: 1...daysInMonth)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                }

                Divider().overlay { Color.white.opacity(0.2) }

                // Summary row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(forecast.projectedAmount.formattedEUR())
                            .font(.title2.bold())
                            .foregroundStyle(.textPrimary)
                        Text("projected this month")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                    }
                    Spacer()
                    let diff = forecast.projectedAmount - forecast.lastThreeMonthAvg
                    if diff != 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(diff > 0
                                ? "+\(diff.formattedEUR())"
                                : "-\(abs(diff).formattedEUR())"
                            )
                            .font(.caption.bold())
                            .foregroundStyle(trendColor)
                            Text("vs 3-month avg")
                                .font(.caption2)
                                .foregroundStyle(.textDim)
                        }
                    }
                }
            }
        }
    }
}
