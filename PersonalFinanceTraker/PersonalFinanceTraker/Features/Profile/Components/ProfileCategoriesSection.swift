import SwiftUI

struct ProfileCategoriesSection: View {
    @Binding var selectedDetent: PresentationDetent
    @Binding var route: ProfileRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CATEGORIES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.textDim)
                .padding(.horizontal, 4)
            Button {
                selectedDetent = .large
                route = .categories
            } label: {
                HStack {
                    Text("Manage Categories")
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.textDim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
