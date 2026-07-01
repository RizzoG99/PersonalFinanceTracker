import SwiftUI

struct ArcGaugeView: View {
    let score: Int
    let scoreColor: Color

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.1, to: 0.1 + 0.8 * Double(score) / 100.0)
                .stroke(
                    LinearGradient(
                        colors: [scoreColor.opacity(0.7), scoreColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .animation(.easeOut(duration: 0.8), value: score)

            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.title3.bold())
                    .foregroundStyle(scoreColor)
                Text("score")
                    .font(.caption2)
                    .foregroundStyle(.textDim)
            }
        }
    }
}
