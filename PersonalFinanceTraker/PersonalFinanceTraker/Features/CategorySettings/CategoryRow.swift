import SwiftUI

struct CategoryRow: View {
    let category: CategoryModel
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                Image(systemName: category.systemImage)
                    .foregroundStyle(category.categoryColor)
                    .frame(width: 24)
                Text(category.name.localizedCategoryDisplay)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
        }
        .buttonStyle(.plain)
    }
}
