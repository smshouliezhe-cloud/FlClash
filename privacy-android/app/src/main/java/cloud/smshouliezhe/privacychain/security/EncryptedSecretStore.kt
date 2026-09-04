package cloud.smshouliezhe.privacychain.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Stores sensitive values as AES-GCM ciphertext while keeping the encryption
 * key inside Android Keystore. The app manifest disables Android backup so the
 * ciphertext is not silently copied to cloud/device-transfer backups.
 */
class EncryptedSecretStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun put(key: String, value: String) {
        require(key.isNotBlank()) { "Secret key must not be blank" }

        if (value.isEmpty()) {
            remove(key)
            return
        }

        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val encrypted = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))

        val payload = listOf(
            Base64.encodeToString(cipher.iv, Base64.NO_WRAP),
            Base64.encodeToString(encrypted, Base64.NO_WRAP),
        ).joinToString(SEPARATOR)

        preferences.edit().putString(key, payload).apply()
    }

    fun get(key: String): String? {
        val payload = preferences.getString(key, null) ?: return null
        val parts = payload.split(SEPARATOR, limit = 2)
        if (parts.size != 2) return null

        return runCatching {
            val iv = Base64.decode(parts[0], Base64.NO_WRAP)
            val encrypted = Base64.decode(parts[1], Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(encrypted), StandardCharsets.UTF_8)
        }.getOrNull()
    }

    fun remove(key: String) {
        preferences.edit().remove(key).apply()
    }

    fun clear() {
        preferences.edit().clear().apply()
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val PREFS_NAME = "privacychain_secrets"
        const val KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "privacychain.aesgcm.v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val SEPARATOR = "."
    }
}
