import SwiftUI

struct ProfileSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.textDim)
            .padding(.horizontal, 4)
    }
}
