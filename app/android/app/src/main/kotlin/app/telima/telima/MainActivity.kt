package app.telima.telima

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "telima/sms_relay").setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(SmsRelayReceiver.PREFS, Context.MODE_PRIVATE)
            when (call.method) {
                "enable" -> {
                    prefs.edit()
                        .putString(SmsRelayReceiver.KEY_TOKEN, call.argument<String>("token"))
                        .putString(SmsRelayReceiver.KEY_URL, call.argument<String>("url"))
                        .apply()
                    if (!granted()) ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECEIVE_SMS), 4242)
                    result.success(granted())
                }
                "disable" -> {
                    val token = prefs.getString(SmsRelayReceiver.KEY_TOKEN, null)
                    prefs.edit().clear().apply()
                    result.success(token)
                }
                "requestPermission" -> {
                    if (!granted()) ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECEIVE_SMS), 4242)
                    result.success(granted())
                }
                "status" -> result.success(mapOf(
                    "enabled" to !prefs.getString(SmsRelayReceiver.KEY_TOKEN, null).isNullOrEmpty(),
                    "granted" to granted(),
                ))
                "flush" -> {
                    Thread { SmsRelayReceiver.flushQueue(applicationContext) }.start()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun granted() =
        ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
}
