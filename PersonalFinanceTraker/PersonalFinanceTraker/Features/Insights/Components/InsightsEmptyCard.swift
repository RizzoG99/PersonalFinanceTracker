import SwiftUI

struct InsightsEmptyCard: View {
    let message: String
    var subtitle: String? = nil

    var body: some View {
        GlassCard {
            VStack(spacing: 4) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.textDim)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.textDim.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 8)
        }
    }
}
