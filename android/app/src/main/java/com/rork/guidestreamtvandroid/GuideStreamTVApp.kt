package com.rork.guidestreamtvandroid

import android.app.Application
import android.util.Log
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.local.DeviceSessionService
import com.rork.guidestreamtvandroid.data.remote.RemoteConfigService
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.PushTokenManager
import com.rork.guidestreamtvandroid.data.repository.ReleaseReminderService
import com.rork.guidestreamtvandroid.data.repository.SocialViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.TeamFavoritesService
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.push.GuideStreamFirebaseMessagingService
import com.rork.guidestreamtvandroid.ui.ads.AdManager
import com.rork.guidestreamtvandroid.widget.WidgetDataService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Application entry point — initializes all singleton services.
 * Mirrors iOS GuideStreamTVApp.swift.
 */
class GuideStreamTVApp : Application() {
    override fun onCreate() {
        super.onCreate()

        // Initialize singletons in dependency order. Each step is guarded so a
        // single failing service can never prevent the app from launching.
        safe("DeviceIdentity") { DeviceIdentity.init(this) }
        safe("RemoteConfig") { RemoteConfigService.init(this) }
        safe("AuthViewModel") { AuthViewModel.init(this) }
        safe("WatchIntentLogger") { WatchIntentLogger.init(this) }
        safe("DeviceSessionService") { DeviceSessionService.init(this) }
        safe("StreamsViewModel") { StreamsViewModel.init(this) }
        safe("SocialViewModel") { SocialViewModel.init(this) }
        safe("ReleaseReminderService") { ReleaseReminderService.init(this) }
        safe("TeamFavoritesService") { TeamFavoritesService.init(this) }
        safe("PushTokenManager") { PushTokenManager.init(this) }
        // Create the gs_episodes notification channel at launch. Production
        // pushes send notification payloads that the Firebase SDK renders
        // itself against this channel id without invoking onMessageReceived —
        // on Android 8+ a notification posted to a nonexistent channel is
        // silently dropped, so the channel must exist before any push arrives.
        // ensureChannel is idempotent (null-checks before creating) and
        // creating a channel never triggers a permission dialog.
        safe("NotificationChannel") { GuideStreamFirebaseMessagingService.ensureChannel(this) }
        safe("WidgetDataService") { WidgetDataService.init(this) }

        // Restore session on cold launch
        safe("restoreSession") { AuthViewModel.get().restoreSession() }

        // Initialize AdMob. The interstitial preload is deferred until
        // after the remote config fetch resolves (with a 2s safety timeout)
        // so the first request uses the remote ad unit id when available.
        // Any failure still results in a preload with fallback values.
        safe("AdMob") {
            AdManager.get().initialize(this)
            adScope.launch {
                withTimeoutOrNull(2000L) {
                    RemoteConfigService.load()
                }
                withContext(Dispatchers.Main) {
                    AdManager.get().preloadInterstitial(this@GuideStreamTVApp)
                }
            }
        }

        // Log app opened + bump session counter
        safe("appOpened") { WatchIntentLogger.get().log(WatchIntentLogger.IntentEventType.APP_OPENED) }
        safe("sessionUpsert") { DeviceSessionService.get().incrementSessionAndUpsert() }
    }

    private val adScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private inline fun safe(step: String, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            Log.e("GuideStreamTVApp", "Startup step '$step' failed: ${t.message}", t)
        }
    }
}
