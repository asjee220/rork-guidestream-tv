package com.rork.guidestreamtvandroid.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.rork.guidestreamtvandroid.MainActivity
import com.rork.guidestreamtvandroid.data.repository.PushTokenManager
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger

/**
 * FCM messaging service — mirrors iOS AppDelegate push handling.
 * Handles incoming push notifications, creates notification channels,
 * and routes deep links when the user taps a notification.
 */
class GuideStreamFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        private const val CHANNEL_ID = "gs_episodes"
        private const val CHANNEL_NAME = "Episode Alerts"

        fun ensureChannel(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager?.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "New episode and watchlist alerts"
                    enableVibration(true)
                }
                manager?.createNotificationChannel(channel)
            }
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        PushTokenManager.get().cacheToken(token)
        PushTokenManager.get().saveToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val title = message.notification?.title
            ?: message.data["title"]
            ?: "GuideStream TV"
        val body = message.notification?.body
            ?: message.data["body"]
            ?: message.data["message"]
            ?: ""
        val deepLink = message.data["deep_link"] ?: message.data["url"]
        showNotification(title, body, deepLink)
    }

    private fun showNotification(title: String, body: String, deepLink: String?) {
        ensureChannel(this)
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (deepLink != null) data = android.net.Uri.parse(deepLink)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setAutoCancel(true)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        val manager = getSystemService(NotificationManager::class.java)
        manager?.notify(System.currentTimeMillis().toInt(), notification)

        if (deepLink != null) {
            WatchIntentLogger.get().log(
                WatchIntentLogger.IntentEventType.DEEPLINK_FIRED,
                metadata = mapOf("source" to "push_notification", "url" to deepLink),
            )
        }
    }
}
