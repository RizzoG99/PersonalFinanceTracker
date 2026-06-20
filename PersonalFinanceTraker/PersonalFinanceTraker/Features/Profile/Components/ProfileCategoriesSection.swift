import SwiftUI

struct ProfileCategoriesSection: View {
    @Binding var selectedDetent: PresentationDetent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CATEGORIES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.textDim)
                .padding(.horizontal, 4)
            NavigationLink {
                CategorySettingsView()
            } label: {
                Text("Manage Categories")
                    .foregroundStyle(.textPrimary)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                selectedDetent = .large
            })
        }
    }
}
