//
//  AnomalyCalloutView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct AnomalyCalloutView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.textMid)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.textDim)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.orange.opacity(0.12))
        )
    }
}

#Preview {
    AnomalyCalloutView(
        message: "Unusually high spending in Week 3: €412.50",
        onDismiss: {}
    )
    .padding()
    .appBackground()
    .preferredColorScheme(.dark)
}
