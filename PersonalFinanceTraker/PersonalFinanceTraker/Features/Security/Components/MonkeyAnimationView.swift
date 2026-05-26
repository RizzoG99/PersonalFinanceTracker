import SwiftUI

struct MonkeyAnimationView: View {
    @Binding var eyesOpen: Bool
    var isShaking: Bool = false
    var isBouncing: Bool = false

    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        ZStack {
            if eyesOpen {
                Text("🐵")
                    .font(.system(size: 100))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                Text("🙈")
                    .font(.system(size: 100))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: eyesOpen)
        .scaleEffect(isBouncing ? 1.15 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.4), value: isBouncing)
        .offset(x: shakeOffset)
        .onChange(of: isShaking) { _, newValue in
            guard newValue else { return }
            withAnimation(.easeInOut(duration: 0.07).repeatCount(5, autoreverses: true)) {
                shakeOffset = 8
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                withAnimation(.easeInOut(duration: 0.1)) { shakeOffset = 0 }
            }
        }
    }
}
