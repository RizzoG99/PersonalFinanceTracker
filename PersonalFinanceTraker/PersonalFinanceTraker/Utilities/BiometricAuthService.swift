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
    
    private let context = LAContext()
    private let kBiometricLockEnabled = "biometric_lock_enabled"
    
    public init() {
        checkBiometrics()
    }
    
    /// Checks if biometric authentication is available on the device
    public func checkBiometrics() {
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            isBiometricsAvailable = true
        } else {
            isBiometricsAvailable = false
        }
    }
    
    /// Attempts to authenticate the user using biometrics
    public func authenticate(completion: @escaping (Bool) -> Void) {
        let reason = "Unlock your financial data"
        
        // If biometric lock is disabled in settings, auto-unlock
        if !isLockEnabled {
            self.isUnlocked = true
            completion(true)
            return
        }
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
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
    
    /// Lock the app (e.g., when going to background)
    public func lock() {
        if isLockEnabled {
            isUnlocked = false
        }
    }
}
