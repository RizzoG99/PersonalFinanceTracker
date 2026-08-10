import SwiftUI

struct TransactionSaveButton: View {
    let title: LocalizedStringKey
    let isValid: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                // Dim text + fill when invalid so the button reads as clearly disabled rather
                // than pale-but-tappable (white-on-light-gray was low contrast and ambiguous).
                .foregroundStyle(isValid ? Color.textPrimary : Color.textPrimary.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding()
                .glassEffect(.regular.tint(isValid ? Color.accentIndigo : Color.gray.opacity(0.5)).interactive())
        }
        .disabled(!isValid)
        .padding(.horizontal)
        .padding(.bottom)
    }
}
