package com.rork.guidestreamtvandroid.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.rork.guidestreamtvandroid.MainActivity
import com.rork.guidestreamtvandroid.data.repository.PushTokenManager
import com.rork.guidestreamtvandroid.data.repository.SportsLiveScoreController
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.R

/**
 * FCM messaging service — mirrors iOS AppDelegate push handling.
 * Handles incoming push notifications, creates notification channels,
 * and routes deep links when the user taps a notification.
 */
class GuideStreamFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        private const val CHANNEL_ID = "gs_episodes"
        private const val CHANNEL_NAME = "Episode Alerts"
        private const val TAG = "GSLiveScore"

        /** notification_type on a score update for the tracked game. */
        const val LIVE_SCORE_UPDATE = "sports_live_update"

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

        // Live-score updates for a tracked game are not alerts. They repaint
        // the ongoing notification in place and must never post a second one —
        // this is the FCM analogue of the APNs liveactivity push the iOS Live
        // Activity gets, and the reason sports_poll_and_notify branches on
        // live_activities.platform.
        if (message.data["notification_type"] == LIVE_SCORE_UPDATE) {
            try {
                SportsLiveScoreController.init(applicationContext).applyPush(message.data)
            } catch (e: Throwable) {
                Log.e(TAG, "live score update failed: ${e.message}")
            }
            return
        }

        val title = message.notification?.title
            ?: message.data["title"]
            ?: "GuideStream TV"
        val body = message.notification?.body
            ?: message.data["body"]
            ?: message.data["message"]
            ?: ""
        val deepLink = message.data["deep_link"] ?: message.data["url"]
        showNotification(title, body, deepLink, message.data)
    }

    /**
     * Builds the tray notification for a foreground push.
     *
     * The whole FCM `data` map is copied onto the intent as extras, matching
     * exactly what the system tray delivers when the app is backgrounded. That
     * way `MainActivity.handleNotificationIntent` sees the same shape on both
     * paths and can prefer the richer fields — `game_id` in particular, which
     * the sports payload carries even though its `deep_link` is a bare
     * `guidestream://sports` with no id.
     */
    private fun showNotification(
        title: String,
        body: String,
        deepLink: String?,
        payload: Map<String, String>,
    ) {
        ensureChannel(this)
        // `payload`, not `data` — inside Intent.apply the name `data` resolves
        // to Intent's own Uri property, not the parameter.
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (deepLink != null) setData(android.net.Uri.parse(deepLink))
            for ((k, v) in payload) putExtra(k, v)
        }
        // Unique request code + FLAG_UPDATE_CURRENT. Intent equality ignores
        // extras, so a fixed request code of 0 made every notification collide:
        // the second push handed back the first one's cached PendingIntent, and
        // tapping it opened whatever the *earlier* notification pointed at.
        val requestCode = System.currentTimeMillis().toInt()
        val pendingIntent = PendingIntent.getActivity(
            this, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.drawable.ic_stat_popcorn)
            .setColor(androidx.core.content.ContextCompat.getColor(this, R.color.gs_notification_accent))
            .setAutoCancel(true)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        val manager = getSystemService(NotificationManager::class.java)
        manager?.notify(requestCode, notification)

        if (deepLink != null) {
            WatchIntentLogger.get().log(
                WatchIntentLogger.IntentEventType.DEEPLINK_FIRED,
                metadata = mapOf("source" to "push_notification", "url" to deepLink),
            )
        }
    }
}
