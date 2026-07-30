import SwiftUI

struct TransactionSaveButton: View {
    let title: LocalizedStringKey
    let isValid: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .frame(maxWidth: .infinity)
                .padding()
                .glassEffect(.regular.tint(isValid ? Color.accentIndigo : Color.gray).interactive())
        }
        .disabled(!isValid)
        .padding(.horizontal)
        .padding(.bottom)
    }
}
