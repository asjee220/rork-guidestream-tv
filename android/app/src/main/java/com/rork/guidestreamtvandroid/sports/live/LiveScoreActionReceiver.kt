package com.rork.guidestreamtvandroid.sports.live

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.rork.guidestreamtvandroid.data.repository.SportsLiveScoreController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Backs the notification's "Stop tracking" action — the Android counterpart of
 * iOS's StopTrackingGameIntent. Like that intent it runs in the app's process
 * without bringing the app to the foreground.
 *
 * goAsync() keeps the broadcast alive past onReceive so the Supabase write has
 * a chance to land; the notification is cancelled first either way, so the card
 * disappears the instant the user taps regardless of the network.
 */
class LiveScoreActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_STOP = "com.rork.guidestreamtvandroid.LIVE_SCORE_STOP"
        const val EXTRA_GAME_ID = "game_id"
        private const val TAG = "GSLiveScore"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_STOP) return
        val gameId = intent.getStringExtra(EXTRA_GAME_ID)
        LiveScoreNotification.cancel(context)

        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                SportsLiveScoreController.init(context).stop()
            } catch (e: Throwable) {
                Log.e(TAG, "stop from notification failed for game=$gameId: ${e.message}")
            } finally {
                pending.finish()
            }
        }
    }
}
