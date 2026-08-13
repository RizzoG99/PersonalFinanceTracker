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
    // ponytail: UIScreen.main is deprecated on iOS 26 in favor of a per-window-scene
    // lookup; keeping it since this view has no window/scene context to source one
    // from, and it's a deprecation warning, not a functional gap. Upgrade if/when
    // this view gains access to a WindowScene (e.g. via @Environment).
    @State private var isCaptured = UIScreen.main.isCaptured
    // Owned here (not by MainTabView) since AuthenticationWrapper is never torn down
    // while the app is running — MainTabView is recreated on every lock/unlock cycle,
    // which would otherwise reset hideAmounts whenever the app is merely backgrounded.
    @State private var appSettings = AppSettings()

    private let pinService = PINService()
    private let backupService = BackupService()
    let modelContainer: ModelContainer

    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.027, blue: 0.071)
                .ignoresSafeArea()

            if !isPINSetup {
                PINSetupView(
                    viewModel: PINSetupViewModel(
                        pinService: pinService,
                        authService: authService,
                        showsOnboardingExtras: true
                    )
                )
                .transition(.opacity)
            } else if authService.isUnlocked {
                MainTabView(modelContainer: modelContainer, appSettings: appSettings)
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

            // ponytail: covers the task-switcher snapshot, which is taken on
            // .inactive (before .background triggers the PIN lock below).
            // Also covers screen recording / AirPlay mirroring via UIScreen.isCaptured.
            if (scenePhase != .active || isCaptured) && !showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPINSetup)
        .animation(.easeInOut(duration: 0.25), value: authService.isUnlocked)
        .animation(.easeInOut(duration: 0.25), value: scenePhase)
        .onAppear {
            // ponytail: unit tests run inside this app as their host process, so this
            // view's real onAppear fires alongside the test bundle. Without this guard,
            // a fresh test-host launch (isPINSetup false, since the host process has no
            // PIN set up) clears the SAME Keychain accounts PINServiceTests/
            // PINEntryViewModelTests write to, at a moment no test-side lock can see —
            // this was the actual cause of two long-flaky PIN tests, not a concurrency
            // bug in PINService itself. Standard XCTest-host detection; skip the
            // production side effect during test runs.
            let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            if !isPINSetup && !isRunningTests {
                try? pinService.clearPIN()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSplash = false
                }
                // `!isUnlocked` matters: the scenePhase→.active trigger below usually
                // fires first and can have finished a successful Face ID well before
                // this 0.8s timer runs. PR #20's isAuthenticating guard only suppresses
                // an *overlapping* second call, so once that first evaluation has
                // completed this timer opened a second prompt on an already-unlocked
                // app — the duplicate cold-launch prompt. Matches the condition the
                // scenePhase trigger already uses.
                if isPINSetup && authService.isBiometricFeatureEnabled && !authService.isUnlocked {
                    authService.authenticate { _ in }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinSetupComplete)) { _ in
            isPINSetup = true
            authService.unlock()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            isCaptured = UIScreen.main.isCaptured
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && isPINSetup {
                authService.lock()
            } else if newPhase == .active && isPINSetup && !authService.isUnlocked {
                if authService.isBiometricFeatureEnabled {
                    authService.authenticate { _ in }
                }
            }
            if newPhase == .active {
                let repo = TransactionActor.make(modelContainer)
                let settings = appSettings
                let service = backupService
                Task {
                    await BackupScheduler.runIfNeeded(repo: repo, settings: settings, backupService: service)
                }
            }
        }
    }
}
