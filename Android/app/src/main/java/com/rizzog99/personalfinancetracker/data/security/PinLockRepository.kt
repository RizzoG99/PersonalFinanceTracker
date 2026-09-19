package com.rizzog99.personalfinancetracker.data.security

import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** What the app lock knows about the stored PIN. */
sealed interface PinLock {
    /** Secure storage has not been read yet — show neither the app nor the lock screen. */
    data object Unknown : PinLock

    /** No usable PIN: never set, removed, or a stored record that was rejected. */
    data object NotSet : PinLock

    data class Set(val secret: PinSecret) : PinLock
}

/**
 * The app's one view of the PIN. Holds the decrypted secret in memory for the process — reading it
 * means a file read plus a Keystore decrypt, which the app-lock gate cannot do on every
 * recomposition — and keeps the [PinSecretStore] itself cache-free so a verify-read after a write
 * genuinely goes back to disk.
 */
class PinLockRepository(
    private val store: PinSecretStore,
    private val preferences: UserPreferencesRepository,
) {
    private val _state = MutableStateFlow<PinLock>(PinLock.Unknown)
    val state: StateFlow<PinLock> = _state.asStateFlow()

    /**
     * Migrates any pre-#128 PIN out of the preferences DataStore, then publishes what is stored.
     *
     * Total on purpose: nothing here may leave the state [PinLock.Unknown], which renders a blank
     * app for the life of the process. An unreadable `user_preferences.preferences_pb` makes
     * `legacyPinEntry`/`removeLegacyPinEntry` throw, and that must degrade to "no PIN this
     * session, migration retries next launch" — which is what frozen iOS does on a Keychain miss.
     */
    suspend fun load() {
        runCatching { migrateLegacyPin(store, preferences) }
        _state.value = runCatching { store.read() }.getOrNull()?.let(PinLock::Set) ?: PinLock.NotSet
    }

    /** Throws when secure storage is unavailable, so the caller can tell the user it did not save. */
    suspend fun setPin(hash: String, salt: String) {
        val secret = PinSecret(hash, salt)
        store.write(secret)
        _state.value = PinLock.Set(secret)
    }

    suspend fun clearPin() {
        store.clear()
        preferences.setBiometricEnabled(false)
        _state.value = PinLock.NotSet
    }
}

/**
 * Moves a PIN written before #128 out of the preferences DataStore. `versionCode 1` has never
 * shipped, so this only ever sees local development installs — but leaving their `pin_hash` /
 * `pin_salt` serialized in `user_preferences.preferences_pb` would defeat the whole change, so it
 * migrates rather than ignores.
 *
 * The order is the crash contract, and every step is idempotent:
 *
 * 1. No legacy keys at all — nothing to do (the steady state after the first successful run).
 * 2. Secure storage already holds a secret — it wins unconditionally and the legacy keys go. This
 *    covers both "crashed after the secure write, before the delete" and "the user set a new PIN
 *    since", and it is why a stale legacy pair can never clobber a newer PIN.
 * 3. An incomplete or blank pair — deleted. Half a pair can never authenticate anything, so
 *    keeping it would only leave secret bytes lying around while claiming a PIN exists.
 * 4. A complete pair — written to secure storage, then read back and compared before the legacy
 *    keys are deleted. The only readable copy is never removed before the secure one is confirmed.
 * 5. The secure write or the verify fails (Keystore unavailable, key invalidated) — the legacy keys
 *    stay and the next launch retries. The app treats the PIN as unset for that session, which is
 *    exactly what frozen iOS does when the Keychain item cannot be read: `isPINSet()` is false and
 *    no gate appears.
 */
internal suspend fun migrateLegacyPin(store: PinSecretStore, preferences: UserPreferencesRepository) {
    val legacy = preferences.legacyPinEntry() ?: return
    if (store.read() != null) {
        preferences.removeLegacyPinEntry()
        return
    }
    val hash = legacy.first?.takeIf { it.isNotBlank() }
    val salt = legacy.second?.takeIf { it.isNotBlank() }
    if (hash == null || salt == null) {
        preferences.removeLegacyPinEntry()
        return
    }
    val secret = PinSecret(hash, salt)
    runCatching { store.write(secret) }.getOrElse { return }
    if (store.read() == secret) preferences.removeLegacyPinEntry()
}
