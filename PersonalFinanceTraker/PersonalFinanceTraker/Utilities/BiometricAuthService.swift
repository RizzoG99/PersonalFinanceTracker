//
//  BiometricAuthService.swift
//  PersonalFinanceTraker
//
//  Created by Gemini CLI on 26/02/26.
//

import Foundation
import LocalAuthentication

/// Seam for testing biometric-dependent view models without real LocalAuthentication
/// hardware — see `FakeBiometricAuthService` in PINSetupViewModelTests.
public protocol BiometricAuthenticating: AnyObject {
    var isBiometricsAvailable: Bool { get }
    var biometricLabel: String { get }
    var isLockEnabled: Bool { get set }
    func authenticateToEnable(completion: @escaping (Bool) -> Void)
}

/// Where the app is in the lock cycle. One value, so a transition is a single
/// `@Published` write: the old pair of booleans had a real intermediate render between
/// them (authenticating already false, unlocked not yet true) that the privacy cover
/// mistook for the user leaving the app.
public enum LockState: Equatable {
    case locked
    case authenticating
    case unlocked
}

/// Service for handling biometric authentication (FaceID / TouchID)
public class BiometricAuthService: ObservableObject, BiometricAuthenticating {

    @Published public private(set) var lockState: LockState = .locked
    @Published public var isBiometricsAvailable = false
    @Published public private(set) var biometricLabel = "Biometrics"
    /// Resolved once in `checkBiometrics()`. `LAContext.biometryType` is only populated
    /// after `canEvaluatePolicy` has run on that context, so reading it from a freshly
    /// made context — as the PIN screen used to, on every render — answers with whatever
    /// the default is rather than what the device has.
    @Published public private(set) var biometricSymbolName = "lock"

    public var isUnlocked: Bool { lockState == .unlocked }
    public var isAuthenticating: Bool { lockState == .authenticating }

    /// True from just before the system biometric UI is presented until the app is active
    /// again. Face ID's own HUD deactivates our scene, and that is not the user leaving —
    /// without this the privacy cover swaps itself in behind every prompt.
    @Published public private(set) var isSystemAuthInFlight = false

    /// How long the app may be away before it asks again. Short absences — checking the
    /// amount in another app and coming straight back — are the common case, and a Face ID
    /// per switch is what makes entering a stack of transactions miserable.
    public static let defaultGraceInterval: TimeInterval = 30
    public var graceInterval: TimeInterval = BiometricAuthService.defaultGraceInterval

    /// Deliberately in memory only. A force-quit loses it, so a cold launch always
    /// challenges; persisting it would hand an attacker a 30-second window after a reboot.
    private var backgroundedAt: Date?

    public var isBiometricFeatureEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "biometric_lock_enabled")
    }

    private let kBiometricLockEnabled = "biometric_lock_enabled"

    public init() {
        checkBiometrics()
    }

    /// Checks if biometric authentication is available on the device
    public func checkBiometrics() {
        let ctx = LAContext()
        var error: NSError?
        isBiometricsAvailable = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch ctx.biometryType {
        case .faceID:
            biometricLabel = "Face ID"
            biometricSymbolName = "faceid"
        case .touchID:
            biometricLabel = "Touch ID"
            biometricSymbolName = "touchid"
        default:
            biometricLabel = "Biometrics"
            biometricSymbolName = "lock"
        }
    }

    /// Attempts to authenticate the user using biometrics
    public func authenticate(completion: @escaping (Bool) -> Void) {
        let reason = "Unlock your financial data"

        guard isLockEnabled else {
            lockState = .unlocked
            completion(true)
            return
        }

        // Cold launch fires this from both onAppear's splash timer and the scenePhase
        // transition to .active; without this guard the second call opens a second,
        // overlapping Face ID prompt while the first is still awaiting the user.
        guard lockState != .authenticating else { return }

        // Create a fresh context for each evaluation (LAContext is single-use).
        let authContext = LAContext()
        var error: NSError?
        guard authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Biometrics are no longer available (enrollment removed or denied in Settings).
            // Disable the lock to avoid leaving the app permanently inaccessible.
            isLockEnabled = false
            lockState = .unlocked
            completion(true)
            return
        }

        isSystemAuthInFlight = true
        lockState = .authenticating
        authContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                // One write for the whole transition: see `LockState`.
                self.lockState = success ? .unlocked : .locked
                completion(success)
            }
        }
    }

    /// Runs a live biometric challenge to confirm biometrics actually work before
    /// enabling the setting (used during onboarding). Unlike `authenticate()`, this
    /// always challenges — it never short-circuits based on `isLockEnabled`, and it
    /// never mutates `isUnlocked` or `isLockEnabled` itself (the caller decides what
    /// to do with the result).
    public func authenticateToEnable(completion: @escaping (Bool) -> Void) {
        let authContext = LAContext()
        var error: NSError?
        guard authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false)
            return
        }

        authContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Enable biometric unlock") { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    /// User setting to enable/disable the lock
    public var isLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: kBiometricLockEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: kBiometricLockEnabled) }
    }

    /// Unlock the app (called after successful PIN entry)
    public func unlock() {
        lockState = .unlocked
    }

    /// Lock the app (e.g., when the grace period has run out)
    public func lock() {
        lockState = .locked
    }

    // MARK: Grace period

    /// The app went to the background. Note when, but do not lock yet — whether this costs
    /// a re-authentication is decided on the way back in, by how long it lasted.
    ///
    /// The privacy cover does not depend on this: it is driven by the scene phase, so the
    /// task-switcher snapshot is covered whether or not the app stays unlocked underneath.
    public func noteBackgrounded(now: Date = Date()) {
        backgroundedAt = now
        // A real backgrounding ends any prompt-related suppression: whatever the system UI
        // was doing, the cover is now correct.
        isSystemAuthInFlight = false
    }

    /// The app is frontmost again. Locks only if it was away longer than `graceInterval`.
    public func relockIfGraceExpired(now: Date = Date()) {
        isSystemAuthInFlight = false
        guard let leftAt = backgroundedAt else { return }
        backgroundedAt = nil
        guard lockState == .unlocked else { return }
        if now.timeIntervalSince(leftAt) >= graceInterval {
            lock()
        }
    }

    /// The device screen locked. The grace period assumes the phone stayed with its owner,
    /// and a locked screen is the moment that stops being a safe assumption — so it is
    /// spent, and the next foreground challenges however brief the absence was.
    public func invalidateGrace() {
        backgroundedAt = nil
        lock()
    }
}
