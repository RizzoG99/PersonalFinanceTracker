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
    @State private var isCaptured = Self.isScreenCaptured()
    // Owned here (not by MainTabView) since AuthenticationWrapper is never torn down
    // while the app is running — the shell below is rebuilt on every lock/unlock cycle,
    // which would otherwise reset hideAmounts whenever the app is merely backgrounded.
    @State private var appSettings = AppSettings()
    @State private var featureDiscovery = FeatureDiscoveryCoordinator()
    /// Owned here for the same reason as `appSettings`: the shell below is destroyed and
    /// rebuilt on every lock/unlock cycle, and the view models (and the state deliberately
    /// lifted into `AppShellModels` to survive that, like `selectedTab`) must not be.
    @State private var shellModels: AppShellModels

    private let pinService = PINService()
    private let backupService = BackupService()
    let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        _shellModels = State(wrappedValue: AppShellModels(modelContainer: modelContainer))
    }

    private var presentsTourAsIPadCard: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        @Bindable var featureDiscovery = featureDiscovery
        let isShowingTourAsCard = Binding(
            get: { featureDiscovery.isShowingTour && presentsTourAsIPadCard },
            set: { isPresented in
                if !isPresented {
                    featureDiscovery.isShowingTour = false
                }
            }
        )
        let isShowingTourFullScreen = Binding(
            get: { featureDiscovery.isShowingTour && !presentsTourAsIPadCard },
            set: { isPresented in
                if !isPresented {
                    featureDiscovery.isShowingTour = false
                }
            }
        )

        ZStack {
            AppBackground()

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
                // iPad gets its own shell (sidebar + inspector); every other idiom keeps the
                // iPhone tab bar. Both bind to the same `shellModels`, so neither can drift.
                //
                // This view is intentionally swapped out for PINEntryView on lock rather than
                // staying mounted underneath it: `.sheet`/`.fullScreenCover` are UIKit modal
                // presentations that sit above their presenting view controller regardless of
                // SwiftUI zIndex, so an open sheet here would render on top of — or bleed through
                // — a same-level PIN overlay instead of being covered by it. State worth keeping
                // across a lock cycle (selectedTab) is lifted into `shellModels` instead; the rest
                // resets, same as any modal being dismissed when a screen relocks.
                Group {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        IPadRootView(models: shellModels, appSettings: appSettings)
                    } else {
                        MainTabView(models: shellModels, appSettings: appSettings)
                    }
                }
                .environment(featureDiscovery)
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
        .fullScreenCover(isPresented: isShowingTourFullScreen) {
            FeatureDiscoveryTourView(
                onboarding: featureDiscovery.manifest.onboarding,
                mediaBaseURL: featureDiscovery.mediaBaseURL,
                onFinish: { destination in featureDiscovery.finishTour(destination: destination) }
            )
        }
        .sheet(isPresented: isShowingTourAsCard) {
            FeatureDiscoveryTourView(
                onboarding: featureDiscovery.manifest.onboarding,
                mediaBaseURL: featureDiscovery.mediaBaseURL,
                onFinish: { destination in featureDiscovery.finishTour(destination: destination) }
            )
            .interactiveDismissDisabled()
            .presentationDetents([.fraction(0.72)])
            .presentationCornerRadius(32)
            .presentationBackground(.clear)
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $featureDiscovery.releaseToPresent, onDismiss: {
            featureDiscovery.dismissWhatsNew()
        }) { release in
            FeatureDiscoveryWhatsNewView(
                release: release,
                mediaBaseURL: featureDiscovery.mediaBaseURL,
                onAction: { destination in
                    featureDiscovery.performReleaseAction(destination: destination)
                },
                onDone: { featureDiscovery.dismissWhatsNew() }
            )
            // .large only: at .medium the release card's illustration gets clipped right at the
            // sheet edge instead of reading as "scroll for more" — the tour view avoids .medium
            // for the same reason (.fraction(0.72)/fullScreen).
            .presentationDetents([.large])
            .presentationBackground { AppBackground() }
        }
        .task(id: isPINSetup && authService.isUnlocked && !showSplash) {
            guard isPINSetup, authService.isUnlocked, !showSplash else { return }
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            await featureDiscovery.loadAndPrepare(appVersion: appVersion)
        }
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
            isCaptured = Self.isScreenCaptured()
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

    // ponytail: single-window app, so "any captured scene" is the scene.
    private static func isScreenCaptured() -> Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.screen.isCaptured }
    }
}
