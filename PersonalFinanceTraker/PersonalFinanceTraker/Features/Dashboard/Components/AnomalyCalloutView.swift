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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.textMid)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // ponytail: combine icon+message into one VoiceOver stop with a "Warning" prefix,
            // scoped to just this pair so the dismiss button below stays independently actionable.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Warning: \(message)"))

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
