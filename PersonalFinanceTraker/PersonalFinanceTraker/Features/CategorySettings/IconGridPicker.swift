import SwiftUI

struct IconGridPicker: View {
    @Binding var selectedSymbol: String
    let colorToken: String
    /// The symbol the category had when the sheet opened. Kept as its own "Current icon"
    /// section while it's outside the catalog (seeded defaults store unfilled variants such
    /// as `cart`), so it stays selectable after the user has tapped something else.
    var pinnedSymbol: String?
    /// Called after a tap sets `selectedSymbol`; Add / CSV import use it to suggest a color.
    var onSelect: ((String) -> Void)?

    @ScaledMetric(relativeTo: .body) private var cellSize: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 18

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: cellSize), spacing: 12)] }

    private var pinnedOutsideCatalog: String? {
        pinnedSymbol.flatMap { CategoryConstants.symbolNames.contains($0) ? nil : $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let pinned = pinnedOutsideCatalog {
                section(title: String(localized: "Current icon"), symbols: [pinned])
            }
            ForEach(CategoryConstants.symbolGroups) { group in
                section(title: group.title, symbols: group.symbols)
            }
        }
        .padding(.vertical, 4)
    }

    private func section(title: String, symbols: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.bold())
                .foregroundStyle(.textMid)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(symbols, id: \.self) { symbol in
                    cell(for: symbol)
                }
            }
        }
    }

    private func cell(for symbol: String) -> some View {
        let color = Color(categoryToken: colorToken)
        let isSelected = selectedSymbol == symbol
        return Button {
            selectedSymbol = symbol
            onSelect?(symbol)
        } label: {
            Image(systemName: symbol)
                // Semibold, as in TravelFormSheet: thin glyphs (percent, laptop) read closer to the
                // filled symbols around them.
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(isSelected ? color : .textMid)
                .frame(width: cellSize, height: cellSize)
                .background(isSelected ? color.opacity(0.25) : Color.surfaceRaised, in: .rect(cornerRadius: 12))
                // Shape, not just tint, marks the selection (works without color perception).
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color.textPrimary : Color.hairline, lineWidth: isSelected ? 2 : 1)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CategoryConstants.symbolLabel(symbol))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Icon picker") {
    @Previewable @State var symbol = "motorcycle.fill"
    Form {
        Section("Icon") {
            IconGridPicker(selectedSymbol: $symbol, colorToken: "categoryOrange")
        }
        .appFormSectionBackground()
    }
    .appFormBackground()
    .background { AppBackground() }
}

#Preview("Icon picker, legacy symbol") {
    @Previewable @State var symbol = "cart"
    Form {
        Section("Icon") {
            IconGridPicker(selectedSymbol: $symbol, colorToken: "categoryGreen", pinnedSymbol: "cart")
        }
        .appFormSectionBackground()
    }
    .appFormBackground()
    .background { AppBackground() }
}
