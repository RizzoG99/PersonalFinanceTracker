import SwiftUI

struct ProfileAvatarView: View {
    let initials: String
    var size: CGFloat = 80

    var body: some View {
        Text(initials)
            .font(.headline)
            .foregroundStyle(.textPrimary)
    }
}
