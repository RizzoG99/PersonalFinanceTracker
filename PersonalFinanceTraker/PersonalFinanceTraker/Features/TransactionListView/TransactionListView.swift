//
//  UndoDeleteBanner.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 14/10/25.
//

import SwiftUI

struct UndoDeleteBanner: View {
    let count: Int
    let progress: Double
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)

            // ponytail: "transaction"/"transactions" plural handled by the catalog's plural variation, not a hand-rolled ternary
            Text("\(count) transaction deleted")
                .font(.subheadline)

            Spacer()

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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.75))
        }
        .foregroundStyle(.white)
    }
}
