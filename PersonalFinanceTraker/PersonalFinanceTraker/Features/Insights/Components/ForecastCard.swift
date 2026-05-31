//
//  ForecastCard.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct ForecastCard: View {
    let forecast: SpendingForecast

    private var isOverPace: Bool {
        forecast.lastThreeMonthAvg > 0 && forecast.projectedAmount > forecast.lastThreeMonthAvg
    }

    private var trendColor: Color { isOverPace ? .negative : .positive }

    var body: some View {
        GlassCard(tint: trendColor) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("At this pace", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("\(forecast.daysLeft) days left")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatEUR(forecast.projectedAmount))
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("projected this month")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }

                Divider().overlay(Color.white.opacity(0.2))

                HStack {
                    Text("3-month avg")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(formatEUR(forecast.lastThreeMonthAvg))
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    let diff = forecast.projectedAmount - forecast.lastThreeMonthAvg
                    if diff != 0 {
                        Text(diff > 0
                            ? "+\(formatEUR(diff))"
                            : "-\(formatEUR(abs(diff)))"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}
