import Testing
import Foundation
import CryptoKit
@testable import PersonalFinanceTraker

struct BackupCryptoTests {
    @Test func sealAndOpenRoundTrip() throws {
        let originalData = "Hello, World!".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)

        let sealed = try BackupCrypto.seal(originalData, using: key)
        let decrypted = try BackupCrypto.open(sealed, using: key)

        #expect(decrypted == originalData)
    }

    @Test func openThrowsWithWrongKey() throws {
        let originalData = "Hello, World!".data(using: .utf8)!
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)

        let sealed = try BackupCrypto.seal(originalData, using: key1)

        #expect(throws: BackupService.BackupError.decryptionFailed) {
            try BackupCrypto.open(sealed, using: key2)
        }
    }

    @Test func openThrowsWithTamperedCiphertext() throws {
        let originalData = "Hello, World!".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)

        var sealed = try BackupCrypto.seal(originalData, using: key)

        // Tamper with a byte in the middle of the ciphertext
        if sealed.count > 20 {
            sealed[sealed.count / 2] ^= 0xFF
        }

        #expect(throws: BackupService.BackupError.decryptionFailed) {
            try BackupCrypto.open(sealed, using: key)
        }
    }

    @Test func openThrowsWithMalformedCiphertext() throws {
        let key = SymmetricKey(size: .bits256)
        let malformed = "not a valid sealed box".data(using: .utf8)!

        #expect(throws: BackupService.BackupError.decryptionFailed) {
            try BackupCrypto.open(malformed, using: key)
        }
    }
}
