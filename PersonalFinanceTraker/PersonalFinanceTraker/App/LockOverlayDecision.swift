//
//  LockOverlayDecision.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// What covers the app, if anything.
enum LockOverlay: Equatable {
    case none
    /// Task-switcher snapshot cover.
    case cover
    case pin
}

/// Which overlay belongs on screen, as a pure function of the state that decides it.
///
/// Extracted from `AuthenticationWrapper` because this is the part that keeps going wrong:
/// it has to tell three superficially identical situations apart — the user leaving the
/// app, Face ID's own HUD deactivating our scene, and the moment just after a successful
/// unlock — and getting it wrong either flashes a splash screen at the user or leaves
/// their balances in the task-switcher snapshot.
enum LockOverlayDecision {
    static func resolve(
        scenePhase: ScenePhase,
        isPINSetup: Bool,
        showSplash: Bool,
        lockState: LockState,
        isSystemAuthInFlight: Bool
    ) -> LockOverlay {
        // The launch splash is already up in-window; a second copy in the overlay window
        // would only cross-fade against it.
        if showSplash { return .none }

        if scenePhase == .active {
            return isPINSetup && lockState != .unlocked ? .pin : .none
        }

        // Not active. Covering is the default — deliberately *not* conditional on being
        // locked, which is the bug this replaces: the app switcher deactivates the scene
        // before it backgrounds it, so a cover that waited for `lock()` left the balances
        // visible for the whole swipe-up gesture and raced the snapshot.
        //
        // The exception is our own biometric prompt: its HUD deactivates the scene, and
        // swapping the cover in behind it reads as a flash. The PIN pad, if set up, is
        // what belongs behind that prompt.
        if isSystemAuthInFlight {
            return isPINSetup && lockState != .unlocked ? .pin : .none
        }
        return .cover
    }
}
