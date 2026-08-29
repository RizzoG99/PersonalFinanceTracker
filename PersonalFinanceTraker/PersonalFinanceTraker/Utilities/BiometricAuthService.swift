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

/// Service for handling biometric authentication (FaceID / TouchID)
public class BiometricAuthService: ObservableObject, BiometricAuthenticating {

    @Published public var isUnlocked = false
    @Published public var isBiometricsAvailable = false
    @Published public private(set) var biometricLabel = "Biometrics"

    public var isBiometricFeatureEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "biometric_lock_enabled")
    }

    private let kBiometricLockEnabled = "biometric_lock_enabled"
    // ponytail: plain Bool guard, not an actor — authenticate() is only ever called
    // from the main thread (SwiftUI onAppear/onChange callbacks). Published so
    // AuthenticationWrapper's `overlay` can tell a self-triggered Face ID scenePhase
    // blip apart from a real backgrounding event.
    @Published public private(set) var isAuthenticating = false

    public init() {
        checkBiometrics()
    }

    /// Checks if biometric authentication is available on the device
    public func checkBiometrics() {
        let ctx = LAContext()
        var error: NSError?
        isBiometricsAvailable = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch ctx.biometryType {
        case .faceID:  biometricLabel = "Face ID"
        case .touchID: biometricLabel = "Touch ID"
        default:       biometricLabel = "Biometrics"
        }
    }

    /// Attempts to authenticate the user using biometrics
    public func authenticate(completion: @escaping (Bool) -> Void) {
        let reason = "Unlock your financial data"

        guard isLockEnabled else {
            isUnlocked = true
            completion(true)
            return
        }

        // Cold launch fires this from both onAppear's splash timer and the scenePhase
        // transition to .active; without this guard the second call opens a second,
        // overlapping Face ID prompt while the first is still awaiting the user.
        guard !isAuthenticating else { return }

        // Create a fresh context for each evaluation (LAContext is single-use).
        let authContext = LAContext()
        var error: NSError?
        guard authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Biometrics are no longer available (enrollment removed or denied in Settings).
            // Disable the lock to avoid leaving the app permanently inaccessible.
            isLockEnabled = false
            isUnlocked = true
            completion(true)
            return
        }

        isAuthenticating = true
        authContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                self.isUnlocked = success
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
        isUnlocked = true
    }

    /// Lock the app (e.g., when going to background)
    public func lock() {
        isUnlocked = false
    }
}
