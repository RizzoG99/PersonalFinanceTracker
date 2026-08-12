import Testing

// ponytail: PINServiceTests, PINEntryViewModelTests, PINSetupViewModelTests, and
// PINConfirmationViewModelTests all share the same global Keychain accounts
// (pft.pin_hash, pft.pin_failures, pft.pin_locked_until, ...). Each suite already
// serializes its own tests via @Suite(.serialized), but Swift Testing still runs
// separate suites concurrently — nothing stopped suite A's `clearPIN()` teardown
// from wiping suite B's in-flight state. Nesting all four as children of this
// suite makes .serialized cascade across all of them (documented, recursive
// behavior), so only one PIN test runs at a time process-wide.
// Upgrade path: give PINService an injectable Keychain account prefix so each
// test/suite gets its own namespace and this shared-suite trick becomes unneeded.
@Suite(.serialized)
struct PINKeychainSerialTests {}

// ponytail: belt-and-suspenders lock for the two tests that stayed flaky under the
// full 393-test run even after the nesting above and an atomic-upsert fix to
// PINService.store() — isolated runs of just these suites always passed, so
// something in the full run still touches Keychain state these tests read/write
// (BackupCryptoTests, DataWipeServiceTests, etc. — different accounts, same
// underlying keychain database). Rather than guess at another framework-level
// lever, this guards exactly the two affected tests directly. Upgrade path: same
// as PINService's injectable-account-prefix note above — remove this once that
// lands and Keychain state is test-instance-scoped.
actor PINTestLock {
    static let shared = PINTestLock()
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
