package com.rork.guidestreamtvandroid.sports.live

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.rork.guidestreamtvandroid.MainActivity
import com.rork.guidestreamtvandroid.R

/**
 * The ongoing notification that stands in for the iOS Live Activity.
 *
 * Android has no Dynamic Island. The closest equivalent is a **Live Update** —
 * an ongoing notification promoted to the status bar chip and the always-on
 * display, added in Android 16 (API 36). On 15 and below the same notification
 * posts as an ordinary ongoing one: still on the lock screen, still updating,
 * just without the chip. Nothing is version-gated except the promotion itself.
 *
 * Live Updates come with hard constraints, and they are the reason this does
 * NOT draw a card like the iOS lock-screen view:
 *   * no custom RemoteViews — a promoted notification with a custom layout is
 *     silently refused promotion, so the score has to live in the standard
 *     title/text slots
 *   * setColorized(false), a content title, ongoing, and a channel above
 *     IMPORTANCE_MIN are all required
 *   * POST_PROMOTED_NOTIFICATIONS must be in the manifest
 */
object LiveScoreNotification {

    const val CHANNEL_ID = "gs_live_scores"
    private const val CHANNEL_NAME = "Live scores"

    /** Fixed id: an update replaces the card rather than stacking a new one. */
    private const val NOTIFICATION_ID = 4711

    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        // IMPORTANCE_DEFAULT, not LOW: a Live Update is ineligible for
        // promotion on a channel at IMPORTANCE_MIN, and the score changing is
        // not something to buzz about, so vibration and sound stay off.
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "The live score of a game you are tracking"
            enableVibration(false)
            setSound(null, null)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    fun post(context: Context, snapshot: LiveScoreSnapshot) {
        ensureChannel(context)
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return

        val openGame = PendingIntent.getActivity(
            context,
            snapshot.gameId.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                data = Uri.parse("guidestream://game/${snapshot.gameId}")
                putExtra("game_id", snapshot.gameId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stop = PendingIntent.getBroadcast(
            context,
            snapshot.gameId.hashCode() + 1,
            Intent(context, LiveScoreActionReceiver::class.java).apply {
                action = LiveScoreActionReceiver.ACTION_STOP
                putExtra(LiveScoreActionReceiver.EXTRA_GAME_ID, snapshot.gameId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val detail = listOf(snapshot.statusDetail, snapshot.broadcast)
            .filter { it.isNotBlank() }
            .joinToString(" · ")

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_popcorn)
            .setColor(androidx.core.content.ContextCompat.getColor(context, R.color.gs_notification_accent))
            .setContentTitle(snapshot.headline)
            .setContentText(detail)
            .setSubText(snapshot.leagueShort.uppercase())
            .setContentIntent(openGame)
            .setOngoing(!snapshot.isFinal)
            .setAutoCancel(false)
            .setColorized(false)
            .setShowWhen(false)
            // Every update reposts the same id; without this the shade
            // re-alerts on each score change.
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(0, "Stop tracking", stop)

        if (snapshot.broadcast.isNotBlank()) {
            builder.addAction(0, "Watch on ${snapshot.broadcast}", openGame)
        }

        if (Build.VERSION.SDK_INT >= 36) {
            builder.setRequestPromotedOngoing(!snapshot.isFinal)
            builder.setShortCriticalText(snapshot.criticalText)
        }

        NotificationManagerCompat.from(context)
            .notify(NOTIFICATION_ID, builder.build())
    }

    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }
}
