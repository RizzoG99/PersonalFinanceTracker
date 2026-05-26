import Foundation
import CryptoKit
import Security

final class PINService {
    private let hashKey = "pft.pin_hash"
    private let saltKey = "pft.pin_salt"

    func setPIN(_ pin: String) throws {
        var saltBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
            throw PINServiceError.keychainError(status: -1)
        }
        let salt = Data(saltBytes)
        let hashData = Data(SHA256.hash(data: Data((pin + salt.base64EncodedString()).utf8)))
        try store(data: salt, forKey: saltKey)
        try store(data: hashData, forKey: hashKey)
    }

    func validatePIN(_ pin: String) -> Bool {
        guard let salt = fetch(forKey: saltKey),
              let storedHash = fetch(forKey: hashKey) else { return false }
        let computed = Data(SHA256.hash(data: Data((pin + salt.base64EncodedString()).utf8)))
        return computed == storedHash
    }

    func isPINSet() -> Bool { fetch(forKey: hashKey) != nil }

    func clearPIN() throws {
        try delete(forKey: hashKey)
        try delete(forKey: saltKey)
    }

    // MARK: - Private Keychain helpers

    private func store(data: Data, forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw PINServiceError.keychainError(status: status) }
    }

    private func fetch(forKey key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func delete(forKey key: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PINServiceError.keychainError(status: status)
        }
    }
}

enum PINServiceError: Error {
    case keychainError(status: OSStatus)
}

extension Notification.Name {
    static let pinSetupComplete = Notification.Name("com.pft.pinSetupComplete")
}
