package com.rizzog99.personalfinancetracker.domain.security

import java.security.SecureRandom
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * Salted PBKDF2 hash for the local app-lock PIN. Only the hash+salt are stored — the PIN
 * itself never touches disk.
 */
object PinCodec {
    private const val ITERATIONS = 120_000
    private const val KEY_LENGTH_BITS = 256

    fun randomSalt(): String {
        val bytes = ByteArray(16)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    fun hash(pin: String, salt: String): String {
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val spec = PBEKeySpec(pin.toCharArray(), salt.toByteArray(), ITERATIONS, KEY_LENGTH_BITS)
        val key = factory.generateSecret(spec).encoded
        return key.joinToString("") { "%02x".format(it) }
    }

    fun matches(pin: String, salt: String, expectedHash: String): Boolean = hash(pin, salt) == expectedHash
}
