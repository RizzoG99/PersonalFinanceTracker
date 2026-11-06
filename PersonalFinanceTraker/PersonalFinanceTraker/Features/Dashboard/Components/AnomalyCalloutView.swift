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
                    // ponytail: message is one free-text string with the amount embedded
                    // (built in DashboardViewModel); blurring the whole sentence is simpler
                    // than restructuring it into separate amount/text parts for one banner.
                    .privacyBlur()
            }
            // ponytail: combine icon+message into one VoiceOver stop with a "Warning" prefix,
            // scoped to just this pair so the dismiss button below stays independently actionable.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Warning: \(message)"))

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.textDim)
                    .frame(width: 12, height: 12)
                    // 44 × 44 tap target, all of its width on the trailing side: iOS also gives a
                    // button taps ~13 pt outside its frame, and at large text sizes any growth
                    // towards the message would let taps on the text dismiss the callout (#266).
                    .padding(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 32))
                    .contentShape(.rect)
            }
            // Cancels the insets in layout, so the icon and the card keep their size.
            .padding(EdgeInsets(top: -16, leading: 0, bottom: -16, trailing: -32))
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
