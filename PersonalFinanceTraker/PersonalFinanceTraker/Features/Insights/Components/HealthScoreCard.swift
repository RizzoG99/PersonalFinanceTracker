import SwiftUI
import Charts

struct HealthScoreCard: View {
    let healthScore: HealthScore
    let snapshots: [HealthScoreSnapshot]
    let onTap: () -> Void

    private var sortedSnapshots: [HealthScoreSnapshot] {
        snapshots.sorted { $0.timestamp < $1.timestamp }
    }

    private var scoreColor: Color {
        switch healthScore.score {
        case 80...100: return .positive
        case 60...79:  return .accentIndigo
        case 40...59:  return .categoryAmber
        default:       return .negative
        }
    }

    private var sparklineColor: Color {
        guard sortedSnapshots.count >= 2,
              let first = sortedSnapshots.first,
              let last = sortedSnapshots.last else { return .accentIndigo }
        if last.score > first.score { return .positive }
        if last.score < first.score { return .negative }
        return .textDim
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                if sortedSnapshots.count >= 2 {
                    sparkline
                }
                HStack(alignment: .top, spacing: 20) {
                    arcGauge
                        .frame(width: 100, height: 100)

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(healthScore.score) / 100")
                                .font(.title2.bold())
                                .foregroundStyle(.textPrimary)
                            Text(healthScore.label)
                                .font(.caption)
                                .foregroundStyle(.textMid)
                        }

                        Divider()
                            .overlay(Color.white.opacity(0.1))

                        ForEach(healthScore.components) { component in
                            componentRow(component)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var sparkline: some View {
        Chart(sortedSnapshots) { snapshot in
            LineMark(
                x: .value("Date", snapshot.timestamp),
                y: .value("Score", snapshot.score)
            )
            .foregroundStyle(sparklineColor)
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .frame(height: 24)
    }

    private var arcGauge: some View {
        ZStack {
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.1, to: 0.1 + 0.8 * Double(healthScore.score) / 100.0)
                .stroke(
                    LinearGradient(
                        colors: [scoreColor.opacity(0.7), scoreColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .animation(.easeOut(duration: 0.8), value: healthScore.score)

            VStack(spacing: 0) {
                Text("\(healthScore.score)")
                    .font(.title3.bold())
                    .foregroundStyle(scoreColor)
                Text("score")
                    .font(.caption2)
                    .foregroundStyle(.textDim)
            }
        }
    }

    private func componentRow(_ component: ScoreComponent) -> some View {
        HStack(spacing: 8) {
            Text(component.name)
                .font(.caption)
                .foregroundStyle(.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.07))
                RoundedRectangle(cornerRadius: 3)
                    .fill(scoreColor.opacity(0.8))
                    .frame(width: 60 * CGFloat(component.score) / CGFloat(component.max), height: 5)
            }
            .frame(width: 60, height: 5)

            Text("\(component.score)")
                .font(.caption.bold())
                .foregroundStyle(.textMid)
                .frame(width: 20, alignment: .trailing)
        }
    }
}
