import SwiftUI

struct TransactionSaveButton: View {
    let title: LocalizedStringKey
    let isValid: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                // Primary actions use an explicit on-tint foreground. Adaptive screen ink
                // turns dark in light appearance and is not readable on accent indigo.
                .foregroundStyle(isValid ? Color.primaryActionForeground : Color.textMid)
                .frame(maxWidth: .infinity)
                .padding()
                .glassEffect(.regular.tint(isValid ? Color.accentIndigo : Color.gray.opacity(0.5)).interactive())
        }
        .disabled(!isValid)
        .padding(.horizontal)
        .padding(.bottom)
    }
}
