//
//  SplashView.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// Animated launch splash: app icon scales/fades in with a soft indigo glow,
/// app name fades up beneath it. Shown by `AuthenticationWrapper` while it
/// decides whether to route to the lock screen or straight to the dashboard.
struct SplashView: View {
    /// The launch splash animates in. The same view is reused as the privacy cover, where
    /// it appears many times a session, always mid-transition and never looked at for long
    /// — there the spring is only work competing with the system's own animation.
    var animated: Bool = true

    @State private var appeared = false

    var body: some View {
        AppBackground()
            .overlay {
                VStack(spacing: 16) {
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .accentIndigo.opacity(0.5), radius: 30)
                        .scaleEffect(appeared ? 1 : 0.85)
                        .opacity(appeared ? 1 : 0)

                    Text("Personal Finance Tracker")
                        .font(.title2.bold())
                        .foregroundStyle(.textPrimary)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)
                }
            }
            .onAppear {
                guard animated else {
                    appeared = true
                    return
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    appeared = true
                }
            }
    }
}

#Preview {
    SplashView()
}
