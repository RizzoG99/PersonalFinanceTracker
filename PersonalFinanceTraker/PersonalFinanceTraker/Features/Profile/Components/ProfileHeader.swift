import SwiftUI

struct ProfileHeader: View {
    let displayName: String
    let memberSince: String

    var body: some View {
        VStack(spacing: 4) {
            Text(displayName)
                .font(.title3.weight(.bold))
                .foregroundStyle(.textPrimary)
            Text(memberSince)
                .font(.subheadline)
                .foregroundStyle(.textDim)
        }
    }
}
