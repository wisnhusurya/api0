package com.actionpay.api0.ciphers

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import android.util.Log
import java.security.Key
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.random.Random


@SuppressLint("ApplySharedPref")
class StorageCipher18Implementation(context: Context) : StorageCipher {
    private var secretKey: Key = SecretKeySpec(Random.nextBytes(ByteArray(16)), "AES")
    private val cipher: Cipher
    private val secureRandom: SecureRandom

    @Throws(Exception::class)
    override fun encrypt(input: ByteArray): ByteArray? {
        val iv = ByteArray(ivSize)
        secureRandom.nextBytes(iv)
        val ivParameterSpec = IvParameterSpec(iv)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey, ivParameterSpec)
        val payload: ByteArray = cipher.doFinal(input)
        val combined = ByteArray(iv.size + payload.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(payload, 0, combined, iv.size, payload.size)
        return combined
    }

    @Throws(Exception::class)
    override fun decrypt(input: ByteArray): ByteArray? {
        val iv = ByteArray(ivSize)
        System.arraycopy(input, 0, iv, 0, iv.size)
        val ivParameterSpec = IvParameterSpec(iv)
        val payloadSize = input.size - ivSize
        val payload = ByteArray(payloadSize)
        System.arraycopy(input, iv.size, payload, 0, payloadSize)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, ivParameterSpec)
        return cipher.doFinal(payload)
    }

    companion object {
        private const val ivSize = 16
        private const val keySize = 16
        private const val KEY_ALGORITHM = "AES"
        private const val AES_PREFERENCES_KEY = "VGhpcyBpcyB0aGUga2V5IGZvciBhIHNlY3VyZSBzdG9yYWdlIEFFUyBLZXkK"
        private const val SHARED_PREFERENCES_NAME = "FlutterSecureKeyStorage"
        fun moveSecretFromPreferencesIfNeeded(oldPreferences: SharedPreferences, context: Context) {
            val existedSecretKey: String = oldPreferences.getString(AES_PREFERENCES_KEY, null)
                    ?: return
            val oldEditor: SharedPreferences.Editor = oldPreferences.edit()
            oldEditor.remove(AES_PREFERENCES_KEY)
            oldEditor.commit()
            val newPreferences: SharedPreferences = context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE)
            val newEditor: SharedPreferences.Editor = newPreferences.edit()
            newEditor.putString(AES_PREFERENCES_KEY, existedSecretKey)
            newEditor.commit()
        }
    }

    init {
        secureRandom = SecureRandom()
        val rsaCipher = RSACipher18Implementation(context)
        val preferences: SharedPreferences = context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE)
        val editor: SharedPreferences.Editor = preferences.edit()
        val aesKey: String? = preferences.getString(AES_PREFERENCES_KEY, null)
        cipher = Cipher.getInstance("AES/CBC/PKCS7Padding")
        if (aesKey != null) {
            var encrypted: ByteArray
            try {
                encrypted = Base64.decode(aesKey, Base64.DEFAULT)
                secretKey = rsaCipher.unwrap(encrypted, KEY_ALGORITHM)
            } catch (e: Exception) {
                Log.e("StorageCipher18Impl", "unwrap key failed", e)
            }
        } else {
            val key = ByteArray(keySize)
            secureRandom.nextBytes(key)
            secretKey = SecretKeySpec(key, KEY_ALGORITHM)
            val encryptedKey: ByteArray = rsaCipher.wrap(secretKey)
            editor.putString(AES_PREFERENCES_KEY, Base64.encodeToString(encryptedKey, Base64.DEFAULT))
            editor.commit()
        }
    }
}