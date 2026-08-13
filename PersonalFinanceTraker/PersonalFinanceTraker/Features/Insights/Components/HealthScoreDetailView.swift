import SwiftUI
import Charts

struct HealthScoreDetailView: View {
    let healthScore: HealthScore
    let snapshots: [HealthScoreSnapshotData]
    let payCycleStartDay: Int
    @Binding var ignoreSubscriptions: Bool

    private var sortedSnapshots: [HealthScoreSnapshotData] {
        snapshots.sorted { $0.timestamp < $1.timestamp }
    }

    private var periodText: String {
        let calendar = Calendar.current
        let end = Date.now
        let financialMonths = PayCycleService.financialMonths(count: 6, before: end, startDay: payCycleStartDay, calendar: calendar)
        let start = financialMonths.first?.start ?? end
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let endFmt = DateFormatter()
        endFmt.dateFormat = "MMM d, yyyy"
        return "\(fmt.string(from: start)) – \(endFmt.string(from: end))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    scoreHeader
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

    // MARK: - Score Header

    private var scoreColor: Color {
        switch healthScore.score {
        case 80...100: return .positive
        case 60...79:  return .accentIndigo
        case 40...59:  return .categoryAmber
        default:       return .negative
        }
    }

    private var scoreHeader: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(healthScore.score)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    Text("/ 100")
                        .font(.title3)
                        .foregroundStyle(.textDim)
                    Spacer()
                }
                Text(healthScore.label)
                    .font(.subheadline)
                    .foregroundStyle(.textMid)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().overlay(Color.hairline)
                scoreLegend
            }
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Breakdown")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Text("\(periodText) · 25 pts per metric")
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }

            GlassCard {
                VStack(spacing: 16) {
                    ForEach(healthScore.components) { component in
                        componentRow(component)
                        if component.id != healthScore.components.last?.id {
                            Divider().overlay(Color.hairline)
                        }
                    }

                }
            }
        }
    }

    private var scoreLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Total score guide")
                .font(.caption2)
                .foregroundStyle(.textDim)
            HStack(spacing: 0) {
                legendBand(range: "80–100", label: "Excellent", color: .positive)
                legendBand(range: "60–79", label: "Solid", color: .accentIndigo)
                legendBand(range: "40–59", label: "Progress", color: .categoryAmber)
                legendBand(range: "< 40", label: "Attention", color: .negative)
            }
        }
    }

    private func legendBand(range: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.6))
                .frame(height: 3)
            Text(range)
                .font(.caption2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.surfaceRaised)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentIndigo.opacity(0.8))
                            .frame(
                                width: geo.size.width * CGFloat(component.score) / CGFloat(max(1, component.max)),
                                height: 6
                            )
                    }
                }

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
