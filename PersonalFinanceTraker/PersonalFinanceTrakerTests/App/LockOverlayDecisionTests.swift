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

    // Reported from build 82: the cover worked once, then stopped appearing during the swipe
    // and only showed up once the app had fully backgrounded. The flag meant "a return is in
    // progress" but was only cleared at the *next* background, so it stayed set for the whole
    // time the app was active and suppressed the cover on the following swipe away.
    //
    // Walks two full cycles the way the phases actually arrive.
    @Test func theCoverStillWorksOnTheSecondTripToTheAppSwitcher() {
        var entering = false

        func phase(_ p: ScenePhase) -> LockOverlay {
            entering = LockOverlayDecision.isEnteringForeground(entering, phase: p)
            return resolve(p, state: .unlocked, entering: entering)
        }

        // First swipe away, then back.
        #expect(phase(.inactive) == .cover)
        #expect(phase(.background) == .cover)
        entering = true                     // willEnterForeground
        #expect(phase(.inactive) == .none)  // uncovers during the zoom, on purpose
        #expect(phase(.active) == .none)

        // Second swipe away: this is the one that regressed.
        #expect(phase(.inactive) == .cover)
        #expect(phase(.background) == .cover)
    }

    // `willEnterForeground` lands before the `.inactive` of the same transition, so that
    // phase must not be what clears the flag.
    @Test func inactiveDoesNotClearTheReturningFlag() {
        #expect(LockOverlayDecision.isEnteringForeground(true, phase: .inactive) == true)
        #expect(LockOverlayDecision.isEnteringForeground(true, phase: .active) == false)
        #expect(LockOverlayDecision.isEnteringForeground(true, phase: .background) == false)
    }

    // The launch splash is already up in-window; a second copy would cross-fade with it.
    @Test func splashSuppressesEverything() {
        #expect(resolve(.background, splash: true, state: .locked) == .none)
        #expect(resolve(.active, splash: true, state: .locked) == .none)
    }
}
