package com.actionpay.api0.ciphers

interface StorageCipher {
    fun encrypt(input: ByteArray): ByteArray?
    fun decrypt(input: ByteArray): ByteArray?
}