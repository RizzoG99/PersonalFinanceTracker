import SwiftUI

struct PINPadView: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void

    /// Read here rather than passed in, so no caller has to know about it. 76pt keys make a 340pt
    /// pad, which does not fit a ~370pt landscape viewport alongside a title and the dots; 56pt
    /// keys make 248pt, which does. Still above the 44pt minimum target.
    @Environment(\.verticalSizeClass) private var vSizeClass
    private var key: CGFloat { vSizeClass == .compact ? 56 : 76 }
    private var rowSpacing: CGFloat { vSizeClass == .compact ? 8 : 12 }
    private var columnSpacing: CGFloat { vSizeClass == .compact ? 14 : 20 }

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: columnSpacing) {
                    ForEach(row, id: \.self) { digit in
                        PINKeyButton(label: digit, size: key) { onDigit(digit) }
                    }
                }
            }
            HStack(spacing: columnSpacing) {
                Color.clear.frame(width: key, height: key)
                PINKeyButton(label: "0", size: key) { onDigit("0") }
                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.system(size: key * 0.29, weight: .medium))
                        .foregroundStyle(.textPrimary)
                        .frame(width: key, height: key)
                }
            }
        }
    }
}

private struct PINKeyButton: View {
    let label: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: size * 0.37, weight: .regular))
                .foregroundStyle(.textPrimary)
                .frame(width: size, height: size)
        }
        .buttonStyle(PINKeyStyle())
    }
}

private struct PINKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.bg1.opacity(configuration.isPressed ? 0.8 : 0.4))
                    .overlay(Circle().stroke(Color.textDim.opacity(0.15), lineWidth: 1))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}
