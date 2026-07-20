//
//  AuthenticationWrapper.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct AuthenticationWrapper: View {
    @StateObject private var authService = BiometricAuthService()
    @Environment(\.scenePhase) private var scenePhase

    @State private var isPINSetup: Bool = UserDefaults.standard.bool(forKey: "pin_setup_complete")
    @State private var showSplash = true

    private let pinService = PINService()
    let modelContainer: ModelContainer

    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.027, blue: 0.071)
                .ignoresSafeArea()

            if !isPINSetup {
                PINSetupView(
                    viewModel: PINSetupViewModel(pinService: pinService)
                )
                .transition(.opacity)
            } else if authService.isUnlocked {
                MainTabView(modelContainer: modelContainer)
                    .transition(.opacity)
            } else {
                PINEntryView(
                    viewModel: PINEntryViewModel(pinService: pinService, authService: authService)
                )
                .transition(.opacity)
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPINSetup)
        .animation(.easeInOut(duration: 0.25), value: authService.isUnlocked)
        .onAppear {
            if !isPINSetup {
                try? pinService.clearPIN()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSplash = false
                }
                if isPINSetup && authService.isBiometricFeatureEnabled {
                    authService.authenticate { _ in }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinSetupComplete)) { _ in
            isPINSetup = true
            authService.unlock()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && isPINSetup {
                authService.lock()
            } else if newPhase == .active && isPINSetup && !authService.isUnlocked {
                if authService.isBiometricFeatureEnabled {
                    authService.authenticate { _ in }
                }
            }
        }
    }
}
