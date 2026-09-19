package com.rizzog99.personalfinancetracker.data.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** The PIN's authentication material: the PBKDF2 hash and the salt it was derived with. */
data class PinSecret(val hash: String, val salt: String)

/**
 * Where PIN authentication material lives. The Android peer of iOS's Keychain (#128) — never the
 * ordinary preferences DataStore.
 *
 * [read] returning `null` means "no usable PIN": nothing stored, or a stored record that failed
 * authentication and was rejected. A rejected record is never repaired, guessed at, or partially
 * accepted, and rejecting one leaves the bytes on disk — recovery is setting a PIN again, which
 * overwrites it.
 */
interface PinSecretStore {
    suspend fun read(): PinSecret?

    suspend fun write(secret: PinSecret)

    suspend fun clear()
}

/**
 * Production storage: an AES-256-GCM envelope under a non-exportable `AndroidKeyStore` key, in a
 * file of its own under `filesDir`.
 *
 * Envelope layout, all bytes, no encoding:
 *
 * ```
 * [0]      version (1)
 * [1..12]  GCM nonce, fresh on every write (AndroidKeyStore generates it; callers cannot supply one)
 * [13..]   ciphertext ‖ 16-byte GCM tag over "<hash>\n<salt>"
 * ```
 *
 * The tag is what makes tampering, truncation and a wrong key all fail the same way: `doFinal`
 * throws and [read] answers `null`. Writes land through a temp file plus `rename`, so a crash
 * mid-write leaves the previous envelope intact rather than a half-written one.
 *
 * Nothing here logs: not the PIN, the hash, the salt, the key, the ciphertext, or the reason a
 * record was rejected.
 */
class KeystorePinSecretStore(
    private val file: File,
    private val keyAlias: String = DEFAULT_KEY_ALIAS,
) : PinSecretStore {

    /** Production path: `filesDir/security/pin_secret.bin`, outside every DataStore. */
    constructor(context: Context) : this(File(File(context.filesDir, "security"), "pin_secret.bin"))

    override suspend fun read(): PinSecret? = withContext(Dispatchers.IO) {
        val envelope = runCatching { file.readBytes() }.getOrNull() ?: return@withContext null
        if (envelope.size < MIN_ENVELOPE_BYTES || envelope[0] != ENVELOPE_VERSION) return@withContext null
        val key = existingKey() ?: return@withContext null
        val plaintext = runCatching {
            Cipher.getInstance(TRANSFORMATION).run {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, envelope, 1, NONCE_BYTES))
                doFinal(envelope, 1 + NONCE_BYTES, envelope.size - 1 - NONCE_BYTES)
            }
        }.getOrNull() ?: return@withContext null
        val parts = String(plaintext, Charsets.UTF_8).split(SEPARATOR)
        if (parts.size != 2 || parts.any { it.isEmpty() }) return@withContext null
        PinSecret(parts[0], parts[1])
    }

    override suspend fun write(secret: PinSecret): Unit = withContext(Dispatchers.IO) {
        require(secret.hash.isNotEmpty() && secret.salt.isNotEmpty()) { "empty PIN secret" }
        require(!secret.hash.contains(SEPARATOR) && !secret.salt.contains(SEPARATOR)) { "malformed PIN secret" }
        val cipher = Cipher.getInstance(TRANSFORMATION).apply {
            init(Cipher.ENCRYPT_MODE, existingKey() ?: createKey())
        }
        val ciphertext = cipher.doFinal("${secret.hash}$SEPARATOR${secret.salt}".toByteArray(Charsets.UTF_8))
        val nonce = cipher.iv
        check(nonce.size == NONCE_BYTES) { "unexpected GCM nonce length" }

        file.parentFile?.mkdirs()
        val temp = File(file.parentFile, "${file.name}.tmp")
        FileOutputStream(temp).use { out ->
            out.write(byteArrayOf(ENVELOPE_VERSION))
            out.write(nonce)
            out.write(ciphertext)
            out.flush()
            out.fd.sync()
        }
        check(temp.renameTo(file)) { "could not replace the PIN secret file" }
    }

    override suspend fun clear(): Unit = withContext(Dispatchers.IO) {
        file.delete()
        File(file.parentFile, "${file.name}.tmp").delete()
        // ponytail: the key alias stays. It protects nothing once the envelope is gone, and
        // deleting it is one more way for clear() to fail; the next write reuses it.
        Unit
    }

    private fun existingKey(): SecretKey? = runCatching {
        KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }.getKey(keyAlias, null) as? SecretKey
    }.getOrNull()

    private fun createKey(): SecretKey =
        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE).apply {
            init(
                KeyGenParameterSpec.Builder(
                    keyAlias,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    // Forces a store-generated nonce per encryption, and rejects a reused one.
                    .setRandomizedEncryptionRequired(true)
                    // Deliberately no setUserAuthenticationRequired: biometric enrolment is a
                    // separate, non-secret preference (#128 AC-04) and must not gate PIN storage —
                    // the PIN is the fallback for when biometrics are unavailable.
                    .build(),
            )
        }.generateKey()

    companion object {
        const val DEFAULT_KEY_ALIAS = "pft.pin_secret.v1"
        const val ENVELOPE_VERSION: Byte = 1
        const val NONCE_BYTES = 12

        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_BITS = 128
        private const val SEPARATOR = "\n"

        /** version + nonce + tag + at least one plaintext byte. */
        private const val MIN_ENVELOPE_BYTES = 1 + NONCE_BYTES + (GCM_TAG_BITS / 8) + 1
    }
}
