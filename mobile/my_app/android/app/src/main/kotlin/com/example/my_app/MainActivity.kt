package com.example.my_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "swiftserve/notification_settings").setMethodCallHandler { call, result ->
            if (call.method == "open") {
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                } else {
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:$packageName"))
                }
                startActivity(intent)
                result.success(null)
            } else result.notImplemented()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel("swiftserve_jobs", "Job updates", NotificationManager.IMPORTANCE_DEFAULT))
        }
    }
}
