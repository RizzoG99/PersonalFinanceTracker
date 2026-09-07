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
    /// - Parameter isEnteringForeground: the app is on its way back in — `willEnterForeground`
    ///   has fired but the scene has not become active yet. The whole resume animation happens
    ///   inside that gap, so waiting for `.active` keeps the cover up for the entire zoom and
    ///   delays the first frame underneath it, which is what "the splash takes a while to go"
    ///   actually is.
    static func resolve(
        scenePhase: ScenePhase,
        isPINSetup: Bool,
        showSplash: Bool,
        lockState: LockState,
        isSystemAuthInFlight: Bool,
        isEnteringForeground: Bool = false
    ) -> LockOverlay {
        // The launch splash is already up in-window; a second copy in the overlay window
        // would only cross-fade against it.
        if showSplash { return .none }

        if scenePhase == .active || isEnteringForeground {
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
