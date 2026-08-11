//
//  UndoDeleteBanner.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import SwiftUI

struct UndoDeleteBanner: View {
    let message: String
    let progress: Double
    let onUndo: () -> Void

    var body: some View {
        ToastBanner(
            icon: "trash",
            message: message
        ) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 1 - progress)
                    .stroke(Color.white, lineWidth: 2)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: progress)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)

            Button("Undo", action: onUndo)
                .font(.subheadline.bold())
                .tint(.accentColor)
                .accessibilityLabel("Undo delete")
        }
    }
}
