import SwiftUI
import LocalAuthentication

@Observable @MainActor
final class ProfileViewModel {

    var fullName: String = "" {
        didSet { UserDefaults.standard.set(fullName, forKey: "user_full_name") }
    }

    var isBiometricEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isBiometricEnabled, forKey: "biometric_lock_enabled") }
    }

    private(set) var isBiometricsAvailable: Bool = false
    private(set) var biometricLabel: String = "Biometrics"

    private let memberSinceTimestamp: Double
    private let pinService = PINService()

    var isPINSet: Bool { pinService.isPINSet() }

    init() {
        fullName = UserDefaults.standard.string(forKey: "user_full_name") ?? ""
        isBiometricEnabled = UserDefaults.standard.bool(forKey: "biometric_lock_enabled")
        memberSinceTimestamp = UserDefaults.standard.double(forKey: "member_since_timestamp")
        checkBiometrics()
    }

    /// Re-reads name + biometric preference from UserDefaults. `ProfileViewModel` is created once
    /// at app launch (before onboarding runs) and lives for the whole session, so its initial
    /// snapshot goes stale the moment onboarding writes the real values — call this whenever the
    /// profile screen appears to pick them up.
    func refresh() {
        fullName = UserDefaults.standard.string(forKey: "user_full_name") ?? ""
        isBiometricEnabled = UserDefaults.standard.bool(forKey: "biometric_lock_enabled")
    }

    func checkBiometrics() {
        let ctx = LAContext()
        var error: NSError?
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        isBiometricsAvailable = ctx.biometryType != .none
        switch ctx.biometryType {
        case .faceID:  biometricLabel = "Face ID"
        case .touchID: biometricLabel = "Touch ID"
        default:       biometricLabel = "Biometrics"
        }
    }

    var initials: String {
        let words = fullName.split(separator: " ").prefix(2)
        guard !words.isEmpty else { return "?" }
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var displayName: String {
        fullName.isEmpty ? String(localized: "Your Name") : fullName
    }

    var memberSince: String {
        let ts = memberSinceTimestamp > 0 ? memberSinceTimestamp : Date.now.timeIntervalSince1970
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM yyyy"
        return String(localized: "Member since \(fmt.string(from: Date(timeIntervalSince1970: ts)))")
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date.now)
        let firstName = fullName.split(separator: " ").first.map(String.init) ?? ""
        let salutation: String
        if hour < 12 { salutation = String(localized: "Good morning") }
        else if hour < 17 { salutation = String(localized: "Good afternoon") }
        else { salutation = String(localized: "Good evening") }
        return firstName.isEmpty ? salutation : String(localized: "\(salutation), \(firstName)")
    }
}
