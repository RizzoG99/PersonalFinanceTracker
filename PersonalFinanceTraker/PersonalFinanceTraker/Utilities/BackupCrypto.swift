import Foundation
import CryptoKit
import Security

enum BackupCrypto {
    private static let backupKeyAccount = "pft.backup_key"

    // ponytail: kSecAttrSynchronizable requires the machine running this code to be
    // signed into iCloud with Keychain sync enabled — never guaranteed for a unit-test
    // host (CI, a fresh simulator, a Mac not signed into iCloud), so BackupServiceTests
    // (which exercise this real key()/fetchKey()/storeKey() path, unlike
    // BackupCryptoTests which pass an explicit key) failed there with .keychainError.
    // Store/fetch locally-only under the XCTest host so the encryption round-trip is
    // still exercised without needing real iCloud state; production keeps syncing.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Fetch or create a 256-bit backup encryption key from iCloud Keychain.
    /// Key is stored with synchronization enabled so it syncs to user's other devices.
    static func key() throws -> SymmetricKey {
        if let existingKey = try fetchKey() {
            return existingKey
        }

        let newKey = SymmetricKey(size: .bits256)
        try storeKey(newKey)
        return newKey
    }

    /// Encrypt data using AES-GCM with the backup key.
    /// Returns the combined sealed box (nonce + ciphertext + tag) as Data.
    static func seal(_ data: Data) throws -> Data {
        let key = try Self.key()
        return try seal(data, using: key)
    }

    /// Decrypt data using AES-GCM with the backup key.
    /// Throws `BackupError.decryptionFailed` if the key is wrong or data is tampered.
    static func open(_ data: Data) throws -> Data {
        let key = try Self.key()
        return try open(data, using: key)
    }

    // MARK: - Internal overloads for testing (accessible via @testable)

    /// Encrypt data using AES-GCM with an explicit key (for testing).
    static func seal(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw BackupService.BackupError.sealingFailed
        }
        return combined
    }

    /// Decrypt data using AES-GCM with an explicit key (for testing).
    static func open(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: data)
        } catch {
            // Malformed ciphertext (not even parseable)
            throw BackupService.BackupError.decryptionFailed
        }

        do {
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            // Well-formed ciphertext but authentication failed (wrong key or tampering)
            throw BackupService.BackupError.decryptionFailed
        }
    }

    // MARK: - Private Keychain helpers

    private static func fetchKey() throws -> SymmetricKey? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: backupKeyAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecAttrSynchronizable: isRunningTests ? false : true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            guard let keyData = result as? Data else {
                throw BackupService.BackupError.keychainError
            }
            return SymmetricKey(data: keyData)
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw BackupService.BackupError.keychainError
        }
    }

    private static func storeKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: backupKeyAccount,
            kSecValueData: keyData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable: isRunningTests ? false : true
        ]

        // Delete any existing key first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BackupService.BackupError.keychainError
        }
    }
}

