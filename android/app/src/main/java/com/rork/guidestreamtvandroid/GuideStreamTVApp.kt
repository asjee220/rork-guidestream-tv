package com.rork.guidestreamtvandroid

import android.app.Application
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
        // Initialize singletons in dependency order
        DeviceIdentity.init(this)
        AuthViewModel.init(this)
        WatchIntentLogger.init(this)
        DeviceSessionService.init(this)
        StreamsViewModel.init(this)
        PushTokenManager.init(this)
        WidgetDataService.init(this)

        // Restore session on cold launch
        AuthViewModel.get().restoreSession()

        // Initialize AdMob
        AdManager.get().initialize(this)
        AdManager.get().preloadInterstitial(this)

        // Log app opened + bump session counter
        WatchIntentLogger.get().log(WatchIntentLogger.IntentEventType.APP_OPENED)
        DeviceSessionService.get().incrementSessionAndUpsert()
    }
}
