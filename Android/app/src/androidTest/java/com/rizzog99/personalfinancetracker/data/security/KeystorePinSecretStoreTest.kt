package com.rizzog99.personalfinancetracker.data.security

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import java.io.File
import java.security.KeyStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #128 evidence that needs a real device: the production [KeystorePinSecretStore] against a real
 * `AndroidKeyStore`, a real encrypted file, and real AES-GCM.
 *
 * Everything here works in a test-scoped directory and under a test-scoped key alias, so the
 * installed app's own PIN state and keys are never touched.
 *
 * Method names are plain identifiers, not the backticked sentences the JVM tests use: D8 refuses
 * to dex a lambda whose enclosing method name contains spaces below DEX version 040.
 */
@RunWith(AndroidJUnit4::class)
class KeystorePinSecretStoreTest {

    private lateinit var context: Context
    private lateinit var directory: File
    private lateinit var file: File
    private lateinit var store: KeystorePinSecretStore

    private val secret = PinSecret(hash = "b7c1d4e9f2a68350", salt = "0f3a91cc5d7e24b8")

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        directory = File(context.filesDir, "pin_secret_test").also { it.deleteRecursively() }
        file = File(directory, "pin_secret.bin")
        store = KeystorePinSecretStore(file, KEY_ALIAS)
        deleteKey()
    }

    @After
    fun tearDown() {
        directory.deleteRecursively()
        deleteKey()
    }

    @Test
    fun ac02_secretWrittenThroughAndroidKeystoreReadsBackExactly() = runBlocking {
        assertNull("a store with no file must report no PIN", store.read())

        store.write(secret)

        assertEquals(secret, store.read())
        assertTrue(file.exists())
        // The key that protects it is a real, non-exportable AndroidKeyStore entry.
        val entry = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.getKey(KEY_ALIAS, null)
        assertEquals("AES", entry.algorithm)
        assertNull("an AndroidKeyStore key must not be exportable", entry.encoded)
    }

    @Test
    fun ac01_envelopeOnDiskCarriesNoReadableHashSaltOrPreferenceKeyName() = runBlocking {
        store.write(secret)

        val bytes = file.readBytes()
        assertEquals("version byte", KeystorePinSecretStore.ENVELOPE_VERSION.toInt(), bytes[0].toInt())
        val text = bytes.decodeToString()
        listOf(secret.hash, secret.salt, "pin_hash", "pin_salt").forEach {
            assertFalse("'$it' is readable in the envelope", text.contains(it))
        }
        assertFalse("the envelope must not live in a DataStore file", file.name.endsWith(".preferences_pb"))
        // Discrimination: the same needles do hit the plaintext, so the check above can fail.
        assertTrue("$secret".contains(secret.hash))
    }

    @Test
    fun ac02_newStoreInstanceOverSameFileReadsSecretBackAfterRestart() = runBlocking {
        store.write(secret)

        // A fresh instance holds no state; everything comes from the file plus the Keystore key.
        assertEquals(secret, KeystorePinSecretStore(file, KEY_ALIAS).read())
    }

    @Test
    fun ac02_overwritingWithTheVerySameSecretStillUsesAFreshNonceAndCiphertext() = runBlocking {
        store.write(secret)
        val first = file.readBytes()
        store.write(secret)
        val second = file.readBytes()

        val nonceRange = 1..KeystorePinSecretStore.NONCE_BYTES
        assertNotEquals(
            "the GCM nonce was reused across writes",
            first.slice(nonceRange),
            second.slice(nonceRange),
        )
        assertNotEquals(
            "identical plaintext produced identical ciphertext",
            first.drop(1 + KeystorePinSecretStore.NONCE_BYTES),
            second.drop(1 + KeystorePinSecretStore.NONCE_BYTES),
        )
        assertEquals(secret, store.read())
    }

    @Test
    fun ac02_changingThePinReplacesTheStoredSecretRatherThanKeepingTheOldOne() = runBlocking {
        store.write(secret)
        val changed = PinSecret(hash = "11223344556677889900", salt = "aabbccddeeff")

        store.write(changed)

        assertEquals(changed, store.read())
        assertFalse(file.readBytes().decodeToString().contains(secret.hash))
        assertEquals("no leftover temp envelope", listOf(file.name), directory.list()!!.toList())
    }

    @Test
    fun ac02_removingThePinDeletesTheEncryptedSecret() = runBlocking {
        store.write(secret)

        store.clear()

        assertFalse(file.exists())
        assertNull(store.read())
        // Idempotent: clearing again is not an error.
        store.clear()
        assertNull(store.read())
    }

    @Test
    fun ac02_tamperedTruncatedOrReVersionedEnvelopeIsRejectedAndLeftOnDisk() = runBlocking {
        val cases = mapOf<String, (ByteArray) -> ByteArray>(
            "flipped ciphertext byte" to { it.copyOf().also { b -> b[b.size - 1] = (b[b.size - 1] + 1).toByte() } },
            "flipped GCM tag byte" to { it.copyOf().also { b -> b[b.size - 8] = (b[b.size - 8].toInt() xor 0x5A).toByte() } },
            "flipped nonce byte" to { it.copyOf().also { b -> b[3] = (b[3] + 1).toByte() } },
            "unsupported version" to { it.copyOf().also { b -> b[0] = 9 } },
            "truncated" to { it.copyOf(it.size - 4) },
            "empty" to { ByteArray(0) },
        )

        cases.forEach { (name, corrupt) ->
            store.write(secret)
            val good = file.readBytes()
            assertEquals("precondition for '$name'", secret, store.read())

            file.writeBytes(corrupt(good))
            assertNull("'$name' was accepted", store.read())
            assertTrue("'$name' was destroyed on read instead of rejected", file.exists())

            // Recovery is always the same: set a PIN again, which overwrites the bad envelope.
            store.write(secret)
            assertEquals("could not recover after '$name'", secret, store.read())
            store.clear()
        }
    }

    @Test
    fun ac02_invalidatedKeystoreKeyFailsClosedAndANewPinRestoresTheAppLock() = runBlocking {
        store.write(secret)
        assertEquals(secret, store.read())

        // What a wipe of credentials, a restored backup, or a key invalidation looks like: the
        // envelope is intact but nothing can decrypt it.
        deleteKey()

        assertNull("an undecryptable envelope must not yield a secret", store.read())
        assertTrue(file.exists())

        // Documented recovery: setting a PIN again mints a new key and a new envelope.
        store.write(secret)
        assertEquals(secret, store.read())
    }

    @Test
    fun ac03_legacyDataStorePinMigratesIntoKeystoreStorageAndLeavesNoSerializedTrace() = runBlocking {
        val preferencesFile = File(directory, "legacy.preferences_pb").also { directory.mkdirs() }
        val job = SupervisorJob()
        val dataStore: DataStore<Preferences> =
            PreferenceDataStoreFactory.create(scope = CoroutineScope(Dispatchers.IO + job)) { preferencesFile }
        val preferences = UserPreferencesRepository(dataStore)
        dataStore.edit {
            it[UserPreferencesRepository.LegacyPinKeys.hash] = secret.hash
            it[UserPreferencesRepository.LegacyPinKeys.salt] = secret.salt
        }
        preferences.setUserFullName("Evelyn Boyd Granville")
        assertTrue(preferencesFile.readBytes().decodeToString().contains(secret.hash))

        migrateLegacyPin(store, preferences)
        migrateLegacyPin(store, preferences) // idempotent on a device too

        assertEquals(secret, KeystorePinSecretStore(file, KEY_ALIAS).read())
        val serialized = preferencesFile.readBytes().decodeToString()
        listOf("pin_hash", "pin_salt", secret.hash, secret.salt).forEach {
            assertFalse("'$it' is still serialized in the preferences file", serialized.contains(it))
        }
        assertTrue("unrelated preferences were cleared", serialized.contains("Evelyn Boyd Granville"))
        job.cancelAndJoin()
    }

    private fun deleteKey() {
        runCatching { KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(KEY_ALIAS) }
    }

    private companion object {
        /** Never the production alias: the installed app's own PIN must survive this suite. */
        const val KEY_ALIAS = "pft.pin_secret.instrumentation_test"
    }
}
