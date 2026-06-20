import SwiftUI

struct ColorTokenPicker: View {
    @Binding var selectedToken: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(CategoryConstants.colorTokenNames, id: \.self) { token in
                let color = Color(token)
                Button {
                    selectedToken = token
                } label: {
                    ZStack {
                        Circle()
                            .fill(color)
                            .frame(width: 32, height: 32)
                        if selectedToken == token {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(token)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
