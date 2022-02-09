package com.actionpay.api0.ciphers

import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import android.security.KeyPairGeneratorSpec
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Log
import java.math.BigInteger
import java.security.Key
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.PublicKey
import java.security.cert.Certificate
import java.security.spec.AlgorithmParameterSpec
import java.util.Calendar
import java.util.Locale
import javax.crypto.Cipher
import javax.security.auth.x500.X500Principal

internal class RSACipher18Implementation(context: Context) {
    private val KEY_ALIAS: String
    private var context: Context

    @Throws(Exception::class)
    fun wrap(key: Key?): ByteArray {
        val publicKey: PublicKey = publicKey
        val cipher: Cipher = rSACipher
        cipher.init(Cipher.WRAP_MODE, publicKey)
        return cipher.wrap(key)
    }

    @Throws(Exception::class)
    fun unwrap(wrappedKey: ByteArray?, algorithm: String?): Key {
        val privateKey: PrivateKey = privateKey
        val cipher: Cipher = rSACipher
        cipher.init(Cipher.UNWRAP_MODE, privateKey)
        return cipher.unwrap(wrappedKey, algorithm, Cipher.SECRET_KEY)
    }

    @Throws(Exception::class)
    fun encrypt(input: ByteArray?): ByteArray {
        val publicKey: PublicKey = publicKey
        val cipher: Cipher = rSACipher
        cipher.init(Cipher.ENCRYPT_MODE, publicKey)
        return cipher.doFinal(input)
    }

    @Throws(Exception::class)
    fun decrypt(input: ByteArray?): ByteArray {
        val privateKey: PrivateKey = privateKey
        val cipher: Cipher = rSACipher
        cipher.init(Cipher.DECRYPT_MODE, privateKey)
        return cipher.doFinal(input)
    }

    @get:Throws(Exception::class)
    private val privateKey: PrivateKey
        private get() {
            val ks: KeyStore = KeyStore.getInstance(KEYSTORE_PROVIDER_ANDROID)
            ks.load(null)
            val key = (ks.getKey(KEY_ALIAS, null)
                    ?: throw Exception("No key found under alias: $KEY_ALIAS")) as? PrivateKey
                    ?: throw Exception("Not an instance of a PrivateKey")
            return key as PrivateKey
        }

    @get:Throws(Exception::class)
    private val publicKey: PublicKey
        private get() {
            val ks: KeyStore = KeyStore.getInstance(KEYSTORE_PROVIDER_ANDROID)
            ks.load(null)
            val cert: Certificate = ks.getCertificate(KEY_ALIAS)
                    ?: throw Exception("No certificate found under alias: $KEY_ALIAS")
            return cert.getPublicKey()
                    ?: throw Exception("No key found under alias: $KEY_ALIAS")
        }// error in android 5: NoSuchProviderException: Provider not available: AndroidKeyStoreBCWorkaround

    // error in android 6: InvalidKeyException: Need RSA private or public key
    @get:Throws(Exception::class)
    private val rSACipher: Cipher
        private get() = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            Cipher.getInstance("RSA/ECB/PKCS1Padding", "AndroidOpenSSL") // error in android 6: InvalidKeyException: Need RSA private or public key
        } else {
            Cipher.getInstance("RSA/ECB/PKCS1Padding", "AndroidKeyStoreBCWorkaround") // error in android 5: NoSuchProviderException: Provider not available: AndroidKeyStoreBCWorkaround
        }

    @Throws(Exception::class)
    private fun createRSAKeysIfNeeded(context: Context) {
        val ks: KeyStore = KeyStore.getInstance(KEYSTORE_PROVIDER_ANDROID)
        ks.load(null)
        if (!ks.isKeyEntry(KEY_ALIAS)) {
            createKeys(context)
        }
        // val privateKey: Key = ks.getKey(KEY_ALIAS, null)
        // if (privateKey == null) {
        //    createKeys(context)
        // }
    }

    /**
     * Sets default locale.
     */
    private fun setLocale(locale: Locale) {
        Locale.setDefault(locale)
        val config: Configuration = context.getResources().getConfiguration()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            setSystemLocale(config, locale)
            context = context.createConfigurationContext(config)
        } else {
            setSystemLocaleLegacy(config, locale)
            setContextConfigurationLegacy(context, config)
        }
    }

    @SuppressWarnings("deprecation")
    private fun setContextConfigurationLegacy(context: Context, config: Configuration) {
        context.getResources().updateConfiguration(config, context.getResources().getDisplayMetrics())
    }

    @SuppressWarnings("deprecation")
    private fun setSystemLocaleLegacy(config: Configuration, locale: Locale) {
        config.locale = locale
    }

    @TargetApi(Build.VERSION_CODES.N)
    private fun setSystemLocale(config: Configuration, locale: Locale) {
        config.setLocale(locale)
    }

    @SuppressWarnings("deprecation")
    private fun makeAlgorithmParameterSpecLegacy(context: Context, start: Calendar, end: Calendar): AlgorithmParameterSpec {
        return KeyPairGeneratorSpec.Builder(context)
                .setAlias(KEY_ALIAS)
                .setSubject(X500Principal("CN=$KEY_ALIAS"))
                .setSerialNumber(BigInteger.valueOf(1))
                .setStartDate(start.getTime())
                .setEndDate(end.getTime())
                .build()
    }

    @SuppressLint("NewApi")
    @Throws(Exception::class)
    private fun createKeys(context: Context) {
        Log.i("fluttersecurestorage", "Creating keys!")
        val localeBeforeFakingEnglishLocale: Locale = Locale.getDefault()
        try {
            setLocale(Locale.ENGLISH)
            val start: Calendar = Calendar.getInstance()
            val end: Calendar = Calendar.getInstance()
            end.add(Calendar.YEAR, 25)
            val kpGenerator: KeyPairGenerator = KeyPairGenerator.getInstance(TYPE_RSA, KEYSTORE_PROVIDER_ANDROID)
            var spec: AlgorithmParameterSpec
            spec = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                makeAlgorithmParameterSpecLegacy(context, start, end)
            } else {
                val builder: KeyGenParameterSpec.Builder = KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_DECRYPT or KeyProperties.PURPOSE_ENCRYPT)
                        .setCertificateSubject(X500Principal("CN=$KEY_ALIAS"))
                        .setDigests(KeyProperties.DIGEST_SHA256)
                        .setBlockModes(KeyProperties.BLOCK_MODE_ECB)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_PKCS1)
                        .setCertificateSerialNumber(BigInteger.valueOf(1))
                        .setCertificateNotBefore(start.getTime())
                        .setCertificateNotAfter(end.getTime())
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    builder.setIsStrongBoxBacked(true)
                }
                builder.build()
            }
            try {
                Log.i("fluttersecurestorage", "Initializing")
                kpGenerator.initialize(spec)
                Log.i("fluttersecurestorage", "Generating key pair")
                kpGenerator.generateKeyPair()
            } catch (se: StrongBoxUnavailableException) {
                spec = KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_DECRYPT or KeyProperties.PURPOSE_ENCRYPT)
                        .setCertificateSubject(X500Principal("CN=$KEY_ALIAS"))
                        .setDigests(KeyProperties.DIGEST_SHA256)
                        .setBlockModes(KeyProperties.BLOCK_MODE_ECB)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_PKCS1)
                        .setCertificateSerialNumber(BigInteger.valueOf(1))
                        .setCertificateNotBefore(start.getTime())
                        .setCertificateNotAfter(end.getTime())
                        .build()
                kpGenerator.initialize(spec)
                kpGenerator.generateKeyPair()
            }
        } finally {
            setLocale(localeBeforeFakingEnglishLocale)
        }
    }

    companion object {
        private const val KEYSTORE_PROVIDER_ANDROID = "AndroidKeyStore"
        private const val TYPE_RSA = "RSA"
    }

    init {
        KEY_ALIAS = context.getPackageName().toString() + ".FlutterSecureStoragePluginKey"
        this.context = context
        createRSAKeysIfNeeded(context)
    }
}