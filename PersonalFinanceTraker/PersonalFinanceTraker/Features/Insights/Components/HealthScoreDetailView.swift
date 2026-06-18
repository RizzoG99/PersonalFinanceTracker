import SwiftUI
import Charts

struct HealthScoreDetailView: View {
    let healthScore: HealthScore
    let snapshots: [HealthScoreSnapshot]
    @Binding var ignoreSubscriptions: Bool

    private var sortedSnapshots: [HealthScoreSnapshot] {
        snapshots.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if sortedSnapshots.count >= 2 {
                        historySection
                    }
                    componentsSection
                    toggleSection
                }
                .padding()
            }
            .appBackground()
            .navigationTitle("Health Score")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - History Chart

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score History")
                .font(.headline)
                .foregroundStyle(.textPrimary)

            GlassCard {
                Chart(sortedSnapshots) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Score", snapshot.score)
                    )
                    .foregroundStyle(Color.accentIndigo)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Score", snapshot.score)
                    )
                    .foregroundStyle(Color.accentIndigo)
                    .symbolSize(36)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .foregroundStyle(Color.textDim)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisValueLabel()
                            .foregroundStyle(Color.textDim)
                    }
                }
                .frame(height: 140)
            }
        }
    }

    // MARK: - Component Breakdown

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Breakdown")
                .font(.headline)
                .foregroundStyle(.textPrimary)

            GlassCard {
                VStack(spacing: 16) {
                    ForEach(healthScore.components) { component in
                        componentRow(component)
                        if component.id != healthScore.components.last?.id {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
    }

    private func componentRow(_ component: ScoreComponent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(component.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("\(component.score) / \(component.max)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.textMid)
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.07))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentIndigo.opacity(0.8))
                    .frame(width: max(0, CGFloat(component.score) / CGFloat(component.max)) * 200, height: 6)
            }
            .frame(height: 6)

            Text(component.explanation)
                .font(.caption)
                .foregroundStyle(.textDim)

            if let tip = component.tip {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.categoryAmber)
                    Text(tip)
                        .font(.caption)
                        .foregroundStyle(Color.categoryAmber)
                }
                .padding(8)
                .background(Color.categoryAmber.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Toggle

    private var toggleSection: some View {
        GlassCard {
            Toggle(isOn: $ignoreSubscriptions) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exclude subscriptions from score")
                        .font(.subheadline)
                        .foregroundStyle(.textPrimary)
                    Text("Redistributes those points across the other 3 categories")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
            }
            .tint(Color.accentIndigo)
        }
    }
}
