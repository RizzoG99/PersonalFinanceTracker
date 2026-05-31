import SwiftUI

struct InsightsSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.textDim)
        }
    }
}
