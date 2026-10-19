package com.example.dnsswitch

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "dns").setMethodCallHandler { call, result ->
            val cr = contentResolver
            try {
                when (call.method) {
                    "set" -> {
                        Settings.Global.putString(cr, "private_dns_specifier", call.argument<String>("host"))
                        Settings.Global.putString(cr, "private_dns_mode", "hostname")
                        result.success(true)
                    }
                    "off" -> {
                        Settings.Global.putString(cr, "private_dns_mode", "off")
                        result.success(true)
                    }
                    "auto" -> {
                        Settings.Global.putString(cr, "private_dns_mode", "opportunistic")
                        result.success(true)
                    }
                    "get" -> result.success(
                        mapOf(
                            "mode" to Settings.Global.getString(cr, "private_dns_mode"),
                            "host" to Settings.Global.getString(cr, "private_dns_specifier")
                        )
                    )
                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) {
                result.error("perm", "no WRITE_SECURE_SETTINGS", null)
            }
        }
    }
}
