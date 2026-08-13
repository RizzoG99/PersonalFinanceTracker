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
                    .fill(Color.hairline)
                RoundedRectangle(cornerRadius: 3)
                    .fill(scoreColor.opacity(0.8))
                    .frame(width: 60 * CGFloat(component.score) / CGFloat(component.max), height: 5)
            }
            .frame(width: 60, height: 5)

            Text("\(component.score)/\(component.max)")
                .font(.caption.bold())
                .foregroundStyle(.textMid)
                .frame(width: 35, alignment: .trailing)
        }
    }
}
