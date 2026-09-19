package com.rizzog99.personalfinancetracker.data.security

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * PIN-domain behavior of the secret boundary: [migrateLegacyPin] and [PinLockRepository], driven
 * against a real file-backed preferences DataStore and a [FakePinSecretStore].
 *
 * The fake proves the *domain* rules — ordering, idempotency, what happens when a write fails. It
 * proves nothing about AndroidKeyStore; that evidence lives in the instrumentation test
 * `KeystorePinSecretStoreTest`, which runs the production [KeystorePinSecretStore] on a device.
 */
@RunWith(RobolectricTestRunner::class)
class PinSecureStorageTest {

    private lateinit var context: Context
    private lateinit var file: File
    private var session: StoreSession? = null

    private val legacyHash = "7c2f-hash"
    private val legacySalt = "b41e-salt"

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        file = context.preferencesDataStoreFile("pin_secure_storage")
        file.delete()
    }

    @After
    fun tearDown() = runBlocking {
        session?.close()
        file.delete()
        Unit
    }

    @Test
    fun `AC-01 a complete legacy pair moves into secure storage and leaves the preferences file`() = runBlocking {
        val (store, preferences) = openPreferences()
        store.seedLegacyPin(legacyHash, legacySalt)
        val secrets = FakePinSecretStore()

        migrateLegacyPin(secrets, preferences)

        // The secure write was verified by a read-back before the legacy delete, not assumed.
        assertEquals(listOf("read", "write", "read"), secrets.log.toList())
        assertEquals(PinSecret(legacyHash, legacySalt), secrets.read())
        assertNull(preferences.legacyPinEntry())
    }

    @Test
    fun `AC-03 migration is idempotent and never runs twice against the same install`() = runBlocking {
        val (store, preferences) = openPreferences()
        store.seedLegacyPin(legacyHash, legacySalt)
        val secrets = FakePinSecretStore()

        migrateLegacyPin(secrets, preferences)
        val afterFirst = secrets.log.toList()
        migrateLegacyPin(secrets, preferences)
        migrateLegacyPin(secrets, preferences)

        // The second and third passes find no legacy keys and touch the secret store not at all.
        assertEquals(afterFirst, secrets.log.toList())
        assertEquals(PinSecret(legacyHash, legacySalt), secrets.read())
    }

    @Test
    fun `AC-03 a crash after the secure write leaves the secure value winning on retry`() = runBlocking {
        val (store, preferences) = openPreferences()
        val secrets = FakePinSecretStore()
        // The exact interrupted state: secure storage written, legacy keys not yet deleted. The
        // user then set a *different* PIN, so the stale legacy pair must not come back.
        secrets.write(PinSecret("newer-hash", "newer-salt"))
        store.seedLegacyPin(legacyHash, legacySalt)

        migrateLegacyPin(secrets, preferences)

        assertEquals(PinSecret("newer-hash", "newer-salt"), secrets.read())
        assertNull(preferences.legacyPinEntry())
    }

    @Test
    fun `AC-03 a crash before the secure write is recoverable from the legacy values`() = runBlocking {
        val (store, preferences) = openPreferences()
        store.seedLegacyPin(legacyHash, legacySalt)
        val secrets = FakePinSecretStore(failWrites = true)

        migrateLegacyPin(secrets, preferences)

        // Never delete the only readable copy: the legacy pair survives a failed secure write.
        assertNull(secrets.read())
        assertEquals(legacyHash to legacySalt, preferences.legacyPinEntry())

        // Next launch, with storage back, completes it.
        secrets.failWrites = false
        migrateLegacyPin(secrets, preferences)
        assertEquals(PinSecret(legacyHash, legacySalt), secrets.read())
        assertNull(preferences.legacyPinEntry())
    }

    @Test
    fun `AC-03 a secure write that cannot be read back keeps the legacy values`() = runBlocking {
        val (store, preferences) = openPreferences()
        store.seedLegacyPin(legacyHash, legacySalt)
        // Writes report success but nothing comes back — the fail-closed case the verify exists for.
        val secrets = FakePinSecretStore(swallowWrites = true)

        migrateLegacyPin(secrets, preferences)

        assertEquals(legacyHash to legacySalt, preferences.legacyPinEntry())
    }

    @Test
    fun `AC-03 partial and blank legacy pairs are deleted rather than migrated`() = runBlocking {
        listOf(
            legacyHash to null,
            null to legacySalt,
            "" to legacySalt,
            legacyHash to "   ",
        ).forEach { (hash, salt) ->
            session?.close()
            file.delete()
            val (store, preferences) = openPreferences()
            store.edit {
                if (hash != null) it[UserPreferencesRepository.LegacyPinKeys.hash] = hash
                if (salt != null) it[UserPreferencesRepository.LegacyPinKeys.salt] = salt
            }
            val secrets = FakePinSecretStore()

            migrateLegacyPin(secrets, preferences)

            // Half a pair can never authenticate; keeping it would leave secret bytes on disk
            // while claiming a PIN exists.
            assertNull("half a pair was migrated for $hash / $salt", secrets.read())
            assertNull("half a pair survived for $hash / $salt", preferences.legacyPinEntry())
        }
    }

    @Test
    fun `AC-02 the lock state resolves through the secret store, and set and clear move it`() = runBlocking {
        val (_, preferences) = openPreferences()
        val secrets = FakePinSecretStore()
        val repository = PinLockRepository(secrets, preferences)

        assertEquals(PinLock.Unknown, repository.state.value)
        repository.load()
        assertEquals(PinLock.NotSet, repository.state.value)

        repository.setPin("hash-a", "salt-a")
        assertEquals(PinLock.Set(PinSecret("hash-a", "salt-a")), repository.state.value)
        assertEquals(PinSecret("hash-a", "salt-a"), secrets.read())

        // Overwrite: a changed PIN replaces the secret rather than adding a second one.
        repository.setPin("hash-b", "salt-b")
        assertEquals(PinSecret("hash-b", "salt-b"), secrets.read())

        preferences.setBiometricEnabled(true)
        repository.clearPin()
        assertEquals(PinLock.NotSet, repository.state.value)
        assertNull(secrets.read())
        // Removing the PIN takes biometric unlock with it — it has nothing left to fall back to.
        assertEquals(false, preferences.biometricEnabled.first())
    }

    @Test
    fun `AC-02 a rejected secret reads as no PIN, and setting one again recovers`() = runBlocking {
        val (_, preferences) = openPreferences()
        // What a tampered, truncated or undecryptable envelope looks like to the domain.
        val secrets = FakePinSecretStore(rejectReads = true)
        val repository = PinLockRepository(secrets, preferences)

        repository.load()
        assertEquals(PinLock.NotSet, repository.state.value)

        secrets.rejectReads = false
        repository.setPin("hash-c", "salt-c")
        assertEquals(PinLock.Set(PinSecret("hash-c", "salt-c")), repository.state.value)
    }

    @Test
    fun `AC-02 load always resolves the lock state, even when storage throws`() = runBlocking {
        val (store, preferences) = openPreferences()
        // Legacy keys present, so the throwing read happens inside the migration too. Both halves
        // can throw; leaving the state Unknown would render a blank app for the life of the process.
        store.seedLegacyPin(legacyHash, legacySalt)
        val repository = PinLockRepository(FakePinSecretStore(throwOnRead = true), preferences)

        repository.load()

        assertEquals(PinLock.NotSet, repository.state.value)
        // The failed migration left the legacy values alone for the next launch to retry.
        assertEquals(legacyHash to legacySalt, preferences.legacyPinEntry())
    }

    @Test
    fun `AC-02 a failed secure write surfaces instead of reporting a PIN that was never stored`() = runBlocking {
        val (_, preferences) = openPreferences()
        val repository = PinLockRepository(FakePinSecretStore(failWrites = true), preferences)
        repository.load()

        val result = runCatching { repository.setPin("hash-d", "salt-d") }

        assertTrue("setPin swallowed a storage failure", result.isFailure)
        assertEquals(PinLock.NotSet, repository.state.value)
    }

    private fun openPreferences(): Pair<DataStore<Preferences>, UserPreferencesRepository> {
        val store = StoreSession(file).also { session = it }.store
        return store to UserPreferencesRepository(store)
    }

    private suspend fun DataStore<Preferences>.seedLegacyPin(hash: String, salt: String) {
        edit {
            it[UserPreferencesRepository.LegacyPinKeys.hash] = hash
            it[UserPreferencesRepository.LegacyPinKeys.salt] = salt
        }
    }

    private class StoreSession(file: File) {
        private val job = SupervisorJob()
        private val scope = CoroutineScope(Dispatchers.IO + job)
        val store: DataStore<Preferences> = PreferenceDataStoreFactory.create(scope = scope) { file }

        suspend fun close() = job.cancelAndJoin()
    }
}

/**
 * In-memory [PinSecretStore] for PIN-domain tests, with the three failure modes the production
 * store can actually exhibit: a write that throws (Keystore unavailable), a write that reports
 * success but stores nothing, and a read that rejects what is on disk (tampered or undecryptable).
 */
class FakePinSecretStore(
    var failWrites: Boolean = false,
    var swallowWrites: Boolean = false,
    var rejectReads: Boolean = false,
    var throwOnRead: Boolean = false,
) : PinSecretStore {
    private var secret: PinSecret? = null

    /** Call order, so a test can assert the write really was verified before the legacy delete. */
    val log = mutableListOf<String>()

    override suspend fun read(): PinSecret? {
        log += "read"
        if (throwOnRead) throw java.io.IOException("secure storage unreadable")
        return if (rejectReads) null else secret
    }

    override suspend fun write(secret: PinSecret) {
        log += "write"
        if (failWrites) throw IllegalStateException("secure storage unavailable")
        if (!swallowWrites) this.secret = secret
    }

    override suspend fun clear() {
        log += "clear"
        secret = null
    }
}
