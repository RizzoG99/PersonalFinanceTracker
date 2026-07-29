import SwiftUI

struct ProfileBudgetsSection: View {
    @Binding var selectedDetent: PresentationDetent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BUDGETS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.textDim)
                .padding(.horizontal, 4)
            NavigationLink {
                BudgetsView()
            } label: {
                Text("Manage Budgets")
                    .foregroundStyle(.textPrimary)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                selectedDetent = .large
            })
        }
    }
}
