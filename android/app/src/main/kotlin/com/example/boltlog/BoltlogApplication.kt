package com.example.boltlog

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

/**
 * Ensures FCM's `default` channel exists before the system shows a notification
 * when the app is killed or has never opened the Flutter UI (cold start from push).
 * Must match [lib/services/notification_service.dart] and Cloud Functions `channelId`.
 *
 * Extends [Application] (not io.flutter.app.FlutterApplication): embedding v2 initializes
 * from [MainActivity]; FlutterApplication lives under io.flutter.app and is easy to mis-import.
 */
class BoltlogApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        createDefaultNotificationChannel()
    }

    private fun createDefaultNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "default",
            "Boltlog alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "New requests, offers, and delivery updates"
            enableVibration(true)
            setShowBadge(true)
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }
}
