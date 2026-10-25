import SwiftUI

struct ColorTokenPicker: View {
    @Binding var selectedToken: String

    // Hit target and swatch grow with Dynamic Type; the grid wraps instead of overflowing.
    @ScaledMetric(relativeTo: .body) private var cellSize: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var swatchSize: CGFloat = 32

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize), spacing: 4)], alignment: .leading, spacing: 4) {
            ForEach(CategoryConstants.colorTokenNames, id: \.self) { token in
                let isSelected = selectedToken == token
                Button {
                    selectedToken = token
                } label: {
                    Circle()
                        .fill(Color(categoryToken: token))
                        .frame(width: swatchSize, height: swatchSize)
                        // A ring, not a checkmark: white-on-orange is weak in dark mode, and
                        // textPrimary is legible on the form row in both appearances.
                        .overlay {
                            if isSelected {
                                Circle().strokeBorder(Color.textPrimary, lineWidth: 2).padding(-5)
                            }
                        }
                        .frame(width: cellSize, height: cellSize)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CategoryConstants.colorLabel(token))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("Color picker") {
    @Previewable @State var token = "categoryBrown"
    Form {
        Section("Color") {
            ColorTokenPicker(selectedToken: $token)
        }
        .appFormSectionBackground()
    }
    .appFormBackground()
    .background { AppBackground() }
}
