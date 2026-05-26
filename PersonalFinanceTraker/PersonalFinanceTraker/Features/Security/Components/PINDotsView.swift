import SwiftUI

struct PINDotsView: View {
    let filledCount: Int
    private let total = 4

    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filledCount ? Color.accentIndigo : Color.clear)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.accentIndigo.opacity(0.6), lineWidth: 1.5))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: filledCount)
            }
        }
    }
}
