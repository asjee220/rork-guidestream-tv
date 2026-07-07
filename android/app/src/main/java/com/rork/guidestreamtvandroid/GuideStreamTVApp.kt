package com.rork.guidestreamtvandroid

import android.app.Application
import android.util.Log
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.local.DeviceSessionService
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.PushTokenManager
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.ads.AdManager
import com.rork.guidestreamtvandroid.widget.WidgetDataService

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
        safe("AuthViewModel") { AuthViewModel.init(this) }
        safe("WatchIntentLogger") { WatchIntentLogger.init(this) }
        safe("DeviceSessionService") { DeviceSessionService.init(this) }
        safe("StreamsViewModel") { StreamsViewModel.init(this) }
        safe("PushTokenManager") { PushTokenManager.init(this) }
        safe("WidgetDataService") { WidgetDataService.init(this) }

        // Restore session on cold launch
        safe("restoreSession") { AuthViewModel.get().restoreSession() }

        // Initialize AdMob
        safe("AdMob") {
            AdManager.get().initialize(this)
            AdManager.get().preloadInterstitial(this)
        }

        // Log app opened + bump session counter
        safe("appOpened") { WatchIntentLogger.get().log(WatchIntentLogger.IntentEventType.APP_OPENED) }
        safe("sessionUpsert") { DeviceSessionService.get().incrementSessionAndUpsert() }
    }

    private inline fun safe(step: String, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            Log.e("GuideStreamTVApp", "Startup step '$step' failed: ${t.message}", t)
        }
    }
}
