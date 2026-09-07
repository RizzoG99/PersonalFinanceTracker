//
//  LockOverlayDecisionTests.swift
//  PersonalFinanceTrakerTests
//

import Testing
import SwiftUI
@testable import PersonalFinanceTraker

struct LockOverlayDecisionTests {
    private func resolve(
        _ phase: ScenePhase,
        pin: Bool = true,
        splash: Bool = false,
        state: LockState,
        authInFlight: Bool = false,
        entering: Bool = false
    ) -> LockOverlay {
        LockOverlayDecision.resolve(
            scenePhase: phase,
            isPINSetup: pin,
            showSplash: splash,
            lockState: state,
            isSystemAuthInFlight: authInFlight,
            isEnteringForeground: entering
        )
    }

    // The regression this file exists for: the app switcher deactivates the scene while the
    // app is still unlocked, and the cover used to wait for the lock that only came at
    // `.background` — so the balances were on screen for the whole swipe.
    @Test func inactiveWhileUnlockedIsStillCovered() {
        #expect(resolve(.inactive, state: .unlocked) == .cover)
    }

    @Test func backgroundedWhileUnlockedIsCovered() {
        #expect(resolve(.background, state: .unlocked) == .cover)
    }

    // Face ID's HUD deactivates our own scene. Covering behind it is the flash.
    @Test func systemAuthPromptDoesNotSwapInTheCover() {
        #expect(resolve(.inactive, state: .authenticating, authInFlight: true) == .pin)
    }

    // The moment right after a successful unlock, before the scene phase catches up: still
    // our prompt's doing, so still no cover.
    @Test func settlingAfterASuccessfulUnlockDoesNotFlashTheCover() {
        #expect(resolve(.inactive, state: .unlocked, authInFlight: true) == .none)
    }

    @Test func activeAndLockedShowsThePINPad() {
        #expect(resolve(.active, state: .locked) == .pin)
    }

    @Test func activeAndUnlockedShowsNothing() {
        #expect(resolve(.active, state: .unlocked) == .none)
    }

    // No PIN set up: there is nothing to unlock into, so the pad must never appear.
    @Test func withoutAPINThereIsNoPad() {
        #expect(resolve(.active, pin: false, state: .locked) == .none)
        #expect(resolve(.inactive, pin: false, state: .locked, authInFlight: true) == .none)
        // The cover is not about authentication, so it still applies.
        #expect(resolve(.inactive, pin: false, state: .locked) == .cover)
    }

    // `willEnterForeground` lands at the start of the return animation; the scene only becomes
    // active at its end. Waiting for active keeps the cover up for the whole zoom — which is
    // most of the "why is the splash still there" the recording showed.
    @Test func returningToTheForegroundUncoversBeforeTheSceneIsActive() {
        #expect(resolve(.background, state: .unlocked, entering: true) == .none)
        #expect(resolve(.inactive, state: .unlocked, entering: true) == .none)
    }

    // Same moment, but the grace ran out: the pad renders during the zoom instead of after it.
    @Test func returningLockedShowsThePadDuringTheZoom() {
        #expect(resolve(.background, state: .locked, entering: true) == .pin)
    }

    // The launch splash is already up in-window; a second copy would cross-fade with it.
    @Test func splashSuppressesEverything() {
        #expect(resolve(.background, splash: true, state: .locked) == .none)
        #expect(resolve(.active, splash: true, state: .locked) == .none)
    }
}
