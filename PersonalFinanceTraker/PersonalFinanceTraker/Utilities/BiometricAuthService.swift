//
//  BiometricAuthService.swift
//  PersonalFinanceTraker
//
//  Created by Gemini CLI on 26/02/26.
//

import Foundation
import LocalAuthentication

/// Service for handling biometric authentication (FaceID / TouchID)
public class BiometricAuthService: ObservableObject {
    
    @Published public var isUnlocked = false
    @Published public var isBiometricsAvailable = false
    
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
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        isBiometricsAvailable = ctx.biometryType != .none
    }
    
    /// Attempts to authenticate the user using biometrics
    public func authenticate(completion: @escaping (Bool) -> Void) {
        let reason = "Unlock your financial data"

        guard isLockEnabled else {
            isUnlocked = true
            completion(true)
            return
        }

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

        authContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                self.isUnlocked = success
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
