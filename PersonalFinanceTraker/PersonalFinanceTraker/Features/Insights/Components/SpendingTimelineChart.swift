//
//  SpendingTimelineChart.swift
//  PersonalFinanceTraker
//

import SwiftUI
import Charts

struct SpendingTimelineChart: View {
    @Binding var selectedPeriod: TimePeriod
    let data: [TimelineDataPoint]

    private var labelByDate: [Date: String] {
        Dictionary(uniqueKeysWithValues: data.map { ($0.date, $0.period) })
    }

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
                if data.isEmpty || data.allSatisfy({ $0.expenses == 0 }) {
                    Text("No data")
                        .foregroundStyle(.textDim)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                } else {
                    Chart {
                        ForEach(data) { point in
                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Expenses", point.expenseValue)
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
                                x: .value("Date", point.date),
                                y: .value("Expenses", point.expenseValue)
                            )
                            .foregroundStyle(Color.accentIndigo)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))

                            if point.isSpike {
                                PointMark(
                                    x: .value("Date", point.date),
                                    y: .value("Expenses", point.expenseValue)
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
                        AxisMarks(values: data.map(\.date)) { value in
                            if let date = value.as(Date.self), let label = labelByDate[date] {
                                AxisValueLabel { Text(label).foregroundStyle(.textDim) }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(.textDim)
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
        }
    }
}
