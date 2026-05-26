import SwiftUI

struct PINPadView: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 20) {
                    ForEach(row, id: \.self) { digit in
                        PINKeyButton(label: digit) { onDigit(digit) }
                    }
                }
            }
            HStack(spacing: 20) {
                Color.clear.frame(width: 76, height: 76)
                PINKeyButton(label: "0") { onDigit("0") }
                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.textPrimary)
                        .frame(width: 76, height: 76)
                }
            }
        }
    }
}

private struct PINKeyButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.textPrimary)
                .frame(width: 76, height: 76)
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
