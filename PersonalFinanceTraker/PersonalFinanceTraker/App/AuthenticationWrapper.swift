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
    /// True between `willEnterForeground` and the scene actually becoming active — the whole
    /// resume animation. See `LockOverlayDecision.resolve`.
    @State private var isEnteringForeground = false
    /// Set only by `willEnterForeground`: the app is coming back from the background, which is
    /// the one scene transition that has actually earned a biometric prompt.
    @State private var pendingForegroundAuth = false

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

    private var overlay: LockOverlay {
        LockOverlayDecision.resolve(
            scenePhase: scenePhase,
            isPINSetup: isPINSetup,
            showSplash: showSplash,
            lockState: authService.lockState,
            isSystemAuthInFlight: authService.isSystemAuthInFlight,
            isEnteringForeground: isEnteringForeground
        )
    }

    /// The only place that starts a biometric prompt.
    ///
    /// `isProtectedDataAvailable` is false while the device itself is locked. Asking
    /// LocalAuthentication to evaluate then puts a Face ID sheet over the *lock screen* —
    /// a prompt the user never asked for, on an app they are not looking at. The scene can
    /// still report `.active` in that state (screen locked with the app frontmost, or woken
    /// without being unlocked), so the scene phase alone is not enough to tell.
    ///
    /// Deferred rather than dropped: `protectedDataDidBecomeAvailable` calls this again once
    /// the device is unlocked and the app is actually in front.
    private func authenticateIfNeeded() {
        guard isPINSetup,
              !authService.isUnlocked,
              authService.isBiometricFeatureEnabled,
              UIApplication.shared.isProtectedDataAvailable
        else { return }
        authService.authenticate { _ in }
    }

    private func syncLockOverlay() {
        switch overlay {
        case .none:
            lockOverlay.hide()
        case .cover:
            lockOverlay.show(interactive: false) { SplashView(animated: false) }
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
                authenticateIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinSetupComplete)) { _ in
            isPINSetup = true
            authService.unlock()
        }
        // The device screen locked. Whatever is left of the grace period is spent: it
        // assumes the phone is still in its owner's hands, and this is the event that says
        // otherwise. Fires while backgrounded too, which is the case that matters.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            if isPINSetup { authService.invalidateGrace() }
        }
        // Fires at the *start* of the return animation; `scenePhase == .active` only lands at
        // its end. Deciding here means the shell (or the PIN pad) renders during the zoom
        // rather than after it, and the system stops showing the stale snapshot sooner.
        //
        // Only the overlay is decided here. The biometric prompt still waits for `.active` —
        // LocalAuthentication presents system UI, and asking for it before the scene is active
        // is asking for it to arrive at a bad moment.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            guard isPINSetup else { return }
            authService.relockIfGraceExpired()
            isEnteringForeground = true
            pendingForegroundAuth = true
        }
        // The device was unlocked. This is the moment that covers an auto-lock: the app may
        // never have backgrounded, so there is no `willEnterForeground` to hang the prompt
        // on, but the user has just proved who they are to the device and is looking at us.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            guard scenePhase == .active else { return }
            authenticateIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            isEnteringForeground = LockOverlayDecision.isEnteringForeground(isEnteringForeground, phase: newPhase)
            if newPhase == .background {
                // The keyboard is a system-owned window that draws over ours whatever level we
                // take, so an open keyboard sits on top of the cover, snapshot included, and
                // dismissing it is the only thing that removes it.
                //
                // Here rather than in `syncLockOverlay`: the cover is already up from
                // `.inactive` by now, so `overlay` does not change on the way to `.background`
                // and nothing in that path would run.
                //
                // A catch-all for every other screen with a keyboard — Activity's search field,
                // the bulk-edit sheets. The Add Transaction form does its own, earlier, at
                // `.inactive`, because it is the one that can put focus back afterwards.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                // A return that was started and abandoned before the scene became active has
                // not earned a prompt; leaving this set would hand one to the next `.active`,
                // which may be a blip behind the lock screen.
                pendingForegroundAuth = false
            }
            if newPhase == .background && isPINSetup {
                // Note the time; do not lock yet. Whether coming back costs a Face ID is
                // decided on the way in, by how long this lasted. The cover is already up
                // regardless — it follows the scene phase, not the lock state.
                authService.noteBackgrounded()
            } else if newPhase == .active && isPINSetup {
                authService.relockIfGraceExpired()
                // Only when this `.active` is the end of a real return from the background.
                //
                // An app that was frontmost when the screen locked does not necessarily
                // background: it resigns active, and when the display wakes to the *lock
                // screen* it can go `.active` again behind it. Prompting on any `.active`
                // put a Face ID sheet over the lock screen — and `isProtectedDataAvailable`
                // does not catch it, because the keys are still available in the window
                // right after the device locks.
                if pendingForegroundAuth {
                    pendingForegroundAuth = false
                    authenticateIfNeeded()
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
