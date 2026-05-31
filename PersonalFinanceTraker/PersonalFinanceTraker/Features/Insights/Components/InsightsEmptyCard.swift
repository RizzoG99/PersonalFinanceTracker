import SwiftUI

struct InsightsEmptyCard: View {
    let message: String

    var body: some View {
        GlassCard {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.textDim)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
        }
    }
}
