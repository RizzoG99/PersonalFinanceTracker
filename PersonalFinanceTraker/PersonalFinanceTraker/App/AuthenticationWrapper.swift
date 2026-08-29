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
    // Owned here (not by MainTabView) since AuthenticationWrapper is never torn down
    // while the app is running, and neither is the shell below anymore (see `overlay`) —
    // but keeping ownership here still protects against a future shell rebuild resetting it.
    @State private var appSettings = AppSettings()
    @State private var featureDiscovery = FeatureDiscoveryCoordinator()
    /// Guards the `.task(id:)` below to a single run per launch. The shell now stays mounted
    /// across a lock cycle (see `overlay`), so an open sheet (e.g. Add Transaction) can still be
    /// up on a later unlock — without this, the id's false→true toggle on every unlock would
    /// re-run `loadAndPrepare`, which can set `releaseToPresent`/`isShowingTour` and attempt a
    /// second `.sheet` presentation on top of it ("Currently, only presenting a single sheet is
    /// supported"). Feature discovery is a once-per-launch check anyway, not a per-unlock one.
    @State private var didPrepareFeatureDiscovery = false
    /// Owned here for the same reason as `appSettings`.
    @State private var shellModels: AppShellModels
    /// PIN lock screen and privacy cover render in their own window above the shell — see
    /// `overlay` and `LockOverlayWindow`'s doc comment for why.
    @State private var lockOverlay = LockOverlayWindow()

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

    private enum Overlay: Equatable {
        case none
        /// Task-switcher snapshot cover. Wins over `.pin` so an `.inactive` relock never
        /// flashes the PIN pad mid-transition.
        case cover
        case pin
    }

    private var overlay: Overlay {
        if showSplash { return .none } // splash is already shown in-window
        if scenePhase != .active {
            // Face ID's own evaluatePolicy call causes a brief scenePhase
            // inactive→active blip while it presents (and dismisses) the system HUD —
            // that's not a real backgrounding/task-switcher event, so don't let it
            // flash the (non-interactive) splash cover in. `isUnlocked` is checked
            // separately from `isAuthenticating` (not just `!isAuthenticating &&
            // isUnlocked`): the completion handler sets them in two separate
            // `@Published` writes, so there's a real intermediate render where
            // isAuthenticating has already gone false but isUnlocked hasn't gone true
            // yet — during that gap this used to fall through to `.cover` and show a
            // second splash right after a successful unlock, before scenePhase caught up.
            if authService.isUnlocked {
                return .none
            }
            if authService.isAuthenticating {
                return isPINSetup ? .pin : .none
            }
            return .cover
        }
        if isPINSetup && !authService.isUnlocked { return .pin }
        return .none
    }

    private func syncLockOverlay() {
        switch overlay {
        case .none:
            lockOverlay.hide()
        case .cover:
            lockOverlay.show(interactive: false) { SplashView() }
        case .pin:
            // The software keyboard is its own system-owned window, docked to the screen
            // regardless of our overlay's level — it stays up and hittable, still routing
            // input to the shell's first responder (e.g. the Add Transaction amount field)
            // underneath, unless explicitly dismissed. Verified on-device via the
            // accessibility tree: without this, the keyboard's digit keys stayed reachable
            // while locked, even though the field's contents were correctly hidden.
            //
            // Scoped to `.pin` (not `.cover`): only here is the user actually unauthenticated
            // — a `.cover`-only blip (Control Center, a notification banner) never calls
            // `authService.lock()`, so dismissing the keyboard there would just interrupt
            // typing elsewhere in the app for no security benefit.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            lockOverlay.show(interactive: true) {
                ZStack {
                    AppBackground()
                    PINEntryView(viewModel: PINEntryViewModel(pinService: pinService, authService: authService))
                }
            }
        }
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
                        showsOnboardingExtras: true,
                        restoreRepo: TransactionActor.make(modelContainer),
                        backupService: backupService
                    )
                )
                .transition(.opacity)
            } else {
                // iPad gets its own shell (sidebar + inspector); every other idiom keeps the
                // iPhone tab bar. Both bind to the same `shellModels`, so neither can drift.
                //
                // Stays mounted across a lock cycle — including anything it has presented, like
                // an open Add Transaction sheet — instead of being swapped out for PINEntryView.
                // The lock screen renders in its own window instead (see `overlay`), which is
                // what actually needs to cover this, sheets included.
                //
                // ponytail: this also means the shell now mounts (and its .task/.onAppear work
                // runs) behind the lock on cold launch, before the first unlock — previously it
                // didn't exist yet at that point. Nothing renders visibly (opaque overlay window
                // + accessibilityViewIsModal), so this is a one-time startup-ordering trade for a
                // single code path instead of two; revisit if it ever shows up as a real cost.
                Group {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        IPadRootView(models: shellModels, appSettings: appSettings)
                    } else {
                        MainTabView(models: shellModels, appSettings: appSettings)
                    }
                }
                .environment(featureDiscovery)
                .transition(.opacity)
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPINSetup)
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
            guard isPINSetup, authService.isUnlocked, !showSplash, !didPrepareFeatureDiscovery else { return }
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            await featureDiscovery.loadAndPrepare(appVersion: appVersion)
            // Set only after completing (not before awaiting): if this task gets cancelled
            // mid-flight — id flips back to false, e.g. an instant re-background — the next
            // unlock should retry rather than have permanently skipped the check this session.
            didPrepareFeatureDiscovery = true
        }
        .onChange(of: overlay) { _, _ in syncLockOverlay() }
        .onAppear {
            syncLockOverlay()
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
