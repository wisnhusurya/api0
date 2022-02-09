package com.actionpay.api0

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Base64
import android.util.Log
import androidx.annotation.NonNull
import com.actionpay.api0.ciphers.StorageCipher
import com.actionpay.api0.ciphers.StorageCipher18Implementation
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar
import java.io.PrintWriter
import java.io.StringWriter
import java.nio.charset.Charset
import java.util.HashMap

/** Api0Plugin */
class Api0Plugin: FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel

  private var preferences: SharedPreferences? = null
  private var charset: Charset? = null
  private var storageCipher: StorageCipher? = null

  // Necessary for deferred initialization of storageCipher.
  private var applicationContext: Context? = null
  private var workerThread: HandlerThread? = null
  private var workerThreadHandler: Handler? = null
  private val ELEMENT_PREFERENCES_KEY_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg"
  private val SHARED_PREFERENCES_NAME = "API0"
  private val KEYSTORE_PROVIDER_ANDROID = "AndroidKeyStore"

  fun initInstance(messenger: BinaryMessenger?, context: Context) {
    try {
      applicationContext = context.getApplicationContext()
      preferences = context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE)
      charset = Charset.forName("UTF-8")
      workerThread = HandlerThread("api0.worker")
      workerThread!!.start()
      workerThreadHandler = Handler(workerThread!!.getLooper())
      StorageCipher18Implementation.moveSecretFromPreferencesIfNeeded(preferences!!, context)
      channel = MethodChannel(messenger, "api0")
      channel!!.setMethodCallHandler(this)
    } catch (e: Exception) {
      Log.e("FlutterSecureStoragePl", "Registration failed", e)
    }
  }

  private fun ensureInitStorageCipher() {
    if (storageCipher == null) {
      try {
        Log.d("FlutterSecureStoragePl", "Initializing StorageCipher")
        storageCipher = StorageCipher18Implementation(applicationContext!!)
        Log.d("FlutterSecureStoragePl", "StorageCipher initialization complete")
      } catch (e: Exception) {
        Log.e("FlutterSecureStoragePl", "StorageCipher initialization failed", e)
      }
    }
  }

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    initInstance(flutterPluginBinding.getBinaryMessenger(), flutterPluginBinding.getApplicationContext())
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    val _result = MethodResultWrapper(result)
    // Run all method calls inside the worker thread instead of the platform thread.
    workerThreadHandler!!.post(MethodRunner(call, _result))

    /* if (call.method == "getPlatformVersion") {
      result.success("Android ${android.os.Build.VERSION.RELEASE}")
    } else {
      result.notImplemented()
    } */
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    if (channel != null) {
      if (Build.VERSION.SDK_INT > Build.VERSION_CODES.JELLY_BEAN_MR2) {
        workerThread!!.quitSafely()
      }
      workerThread = null

    }
    channel!!.setMethodCallHandler(null)
    //channel.setMethodCallHandler(null)
  }

  private fun getKeyFromCall(call: MethodCall): String {
    var rawKey: String? = call.argument("key")
    return addPrefixToKey(rawKey!!)
  }


  @Throws(Exception::class)
  private fun readAll(): Map<String, String> {
    val raw: Map<String, String> = preferences!!.getAll() as Map<String, String>
    val all: HashMap<String, String> = HashMap()
    for (entry in raw.entries) {
      val key: String = entry.key.replaceFirst(ELEMENT_PREFERENCES_KEY_PREFIX + '_', "")
      val rawValue: String = entry.value
      val value = decodeRawValue(rawValue)
      all.put(key, value!!)
    }
    return all
  }

  private fun deleteAll() {
    val editor: SharedPreferences.Editor = preferences!!.edit()
    editor.clear()
    editor.commit()
  }

  @Throws(Exception::class)
  private fun write(key: String, value: String) {
    val result: ByteArray = storageCipher!!.encrypt(value.toByteArray(charset!!))!!
    val editor: SharedPreferences.Editor = preferences!!.edit()
    editor.putString(key, Base64.encodeToString(result, 0))
    editor.commit()
  }

  @Throws(Exception::class)
  private fun read(key: String): String? {
    val encoded: String = preferences!!.getString(key, null)!!
    return decodeRawValue(encoded)
  }

  private fun delete(key: String) {
    val editor: SharedPreferences.Editor = preferences!!.edit()
    editor.remove(key)
    editor.commit()
  }

  private fun addPrefixToKey(key: String): String {
    return ELEMENT_PREFERENCES_KEY_PREFIX + "_" + key
  }

  @Throws(Exception::class)
  private fun decodeRawValue(value: String?): String? {
    if (value == null) {
      return null
    }
    val data: ByteArray = Base64.decode(value, 0)
    val result: ByteArray = storageCipher!!.decrypt(data)!!
    return String(result, charset!!)
  }

  internal inner class MethodRunner(call: MethodCall, result: Result) : Runnable {
    private val call: MethodCall
    private val result: Result

    override fun run() {
      try {
        ensureInitStorageCipher()
        when (call.method) {
          "write" -> {
            val key = getKeyFromCall(call)
            val value: String? = call.argument("value")
            write(key, value!!)
            result.success(hashMapOf("resultCode" to "OK", "resultData" to null, "reasonText" to "OK"));
          }
          "read" -> {
            val key = getKeyFromCall(call)
            val value = read(key)
            result.success(hashMapOf("resultCode" to "OK", "resultData" to value, "reasonText" to "OK"));
          }
          "readAll" -> {
            val value = readAll()
            result.success(hashMapOf("resultCode" to "OK", "resultData" to value, "reasonText" to "OK"));
          }
          "delete" -> {
            val key = getKeyFromCall(call)
            delete(key)
            result.success(hashMapOf("resultCode" to "OK", "resultData" to null, "reasonText" to "OK"));
          }
          "deleteAll" -> {
            deleteAll()
            result.success(hashMapOf("resultCode" to "OK", "resultData" to null, "reasonText" to "OK"));
          }
          "getPlatformVersion" -> {
            result.success(hashMapOf("resultCode" to "OK", "resultData" to "Android ${android.os.Build.VERSION.RELEASE}", "reasonText" to "OK"));
          }
          else -> result.notImplemented()
        }
      } catch (e: Exception) {
        val stringWriter = StringWriter()
        e.printStackTrace(PrintWriter(stringWriter))
        result.success(hashMapOf("resultCode" to "FAIL", "resultData" to null, "reasonText" to "call.method: "+call.method+"\n"+stringWriter.toString()));
        //result.error("Exception encountered", call.method, stringWriter.toString())
      }
    }

    init {
      this.call = call
      this.result = result
    }
  }

  internal class MethodResultWrapper(methodResult: Result) : Result {
    private val methodResult: Result
    private val handler: Handler = Handler(Looper.getMainLooper())

    override fun success(result: Any?) {
      handler.post(object : Runnable {
        override fun run() {
          methodResult.success(result)
        }
      })
    }

    override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {
      handler.post(object : Runnable {
        override fun run() {
          methodResult.error(errorCode, errorMessage, errorDetails)
        }
      })
    }

    override fun notImplemented() {
      handler.post(object : Runnable {
        override fun run() {
          methodResult.notImplemented()
        }
      })
    }

    init {
      this.methodResult = methodResult
    }
  }
}
