import SwiftUI
import SwiftData

struct ProfileBudgetsSection: View {
    @Binding var selectedDetent: PresentationDetent
    @Binding var route: ProfileRoute?
    @Query(sort: \CategoryModel.name) private var categories: [CategoryModel]

    private var budgetedCount: Int {
        categories.filter { $0.transactionType == .expense && ($0.monthlyBudget ?? 0) > 0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BUDGETS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.textDim)
                .padding(.horizontal, 4)
            Button {
                selectedDetent = .large
                route = .budgets
            } label: {
                HStack {
                    Text("Manage Budgets")
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    if budgetedCount > 0 {
                        Text("\(budgetedCount) set")
                            .foregroundStyle(.textDim)
                    }
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
