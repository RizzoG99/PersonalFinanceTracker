//
//  SpendingTimelineChart.swift
//  PersonalFinanceTraker
//

import SwiftUI
import Charts

struct SpendingTimelineChart: View {
    @Binding var selectedPeriod: TimePeriod
    let data: [TimelineDataPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spending")
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                    Text("Financial heartbeat")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
                Spacer()
                TimePeriodPicker(selection: $selectedPeriod)
                    .frame(maxWidth: 200)
            }

            GlassCard {
                if data.isEmpty {
                    Text("No data")
                        .foregroundStyle(.textDim)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                } else {
                    Chart {
                        ForEach(data) { point in
                            let expenseDouble = Double(truncating: point.expenses as NSDecimalNumber)

                            AreaMark(
                                x: .value("Period", point.period),
                                y: .value("Expenses", expenseDouble)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.accentIndigo.opacity(0.3), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Period", point.period),
                                y: .value("Expenses", expenseDouble)
                            )
                            .foregroundStyle(Color.accentIndigo)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))

                            if point.isSpike {
                                PointMark(
                                    x: .value("Period", point.period),
                                    y: .value("Expenses", expenseDouble)
                                )
                                .foregroundStyle(Color.negative)
                                .symbolSize(60)
                                .annotation(position: .top) {
                                    Text("⚡")
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(.textDim)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(.textDim)
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        }
                    }
                    .frame(height: 220)
                }
            }
        }
    }
}
