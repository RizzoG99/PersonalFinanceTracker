import SwiftUI

struct ScoreComponentRow: View {
    let component: ScoreComponent
    let scoreColor: Color

    var body: some View {
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
