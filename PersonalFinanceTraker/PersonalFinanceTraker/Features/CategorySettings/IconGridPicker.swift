import SwiftUI

struct IconGridPicker: View {
    @Binding var selectedSymbol: String
    let colorToken: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    // Prepend current symbol if it isn't in the curated list so it's always visible
    private var symbols: [String] {
        if CategoryConstants.symbolNames.contains(selectedSymbol) {
            return CategoryConstants.symbolNames
        }
        return [selectedSymbol] + CategoryConstants.symbolNames
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(symbols, id: \.self) { symbol in
                let color = CategoryConstants.color(forToken: colorToken)
                let isSelected = selectedSymbol == symbol
                Button {
                    selectedSymbol = symbol
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? color.opacity(0.25) : Color.white.opacity(0.06))
                            .frame(width: 44, height: 44)
                        Image(systemName: symbol)
                            .foregroundStyle(isSelected ? color : .textDim)
                            .font(.system(size: 18))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
            }
        }
        .padding(.vertical, 4)
    }
}
