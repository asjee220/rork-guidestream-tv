package com.rork.guidestreamtvandroid

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import com.rork.guidestreamtvandroid.data.DeviceLocale
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.local.DeviceSessionService
import com.rork.guidestreamtvandroid.data.remote.RemoteConfigService
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.PushTokenManager
import com.rork.guidestreamtvandroid.data.repository.ReelsBadgeService
import com.rork.guidestreamtvandroid.data.repository.ReleaseReminderService
import com.rork.guidestreamtvandroid.data.repository.SocialViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.TeamFavoritesService
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.push.GuideStreamFirebaseMessagingService
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
        safe("DeviceLocale") { DeviceLocale.init(this) }
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
        safe("ReelsBadgeService") { ReelsBadgeService.init(this) }

        // Restore session on cold launch
        safe("restoreSession") { AuthViewModel.get().restoreSession() }

        // AdMob now starts from MainActivity.onCreate: UMP consent is
        // gathered there (after the remote config await with the same 2s
        // safety timeout) before the SDK initializes, so no ad request can
        // fire before consent is resolved.

        // Log app opened + bump session counter
        safe("appOpened") { WatchIntentLogger.get().log(WatchIntentLogger.IntentEventType.APP_OPENED) }
        safe("sessionUpsert") { DeviceSessionService.get().incrementSessionAndUpsert() }

        // Track foreground/background transitions via activity lifecycle.
        // A rise from zero to one started-activity means the app returned to
        // the foreground; a return to zero means it went to the background.
        // This replaces ProcessLifecycleOwner (no extra Gradle dependency).
        safe("activityLifecycle") {
            registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
                override fun onActivityStarted(activity: Activity) {
                    startedActivityCount++
                    if (startedActivityCount == 1) {
                        DeviceSessionService.get().handleForeground()
                    }
                }

                override fun onActivityStopped(activity: Activity) {
                    startedActivityCount--
                    if (startedActivityCount == 0) {
                        DeviceSessionService.get().noteBackgrounded()
                    }
                }

                override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
                override fun onActivityResumed(activity: Activity) {}
                override fun onActivityPaused(activity: Activity) {}
                override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
                override fun onActivityDestroyed(activity: Activity) {}
            })
        }
    }

    @Volatile private var startedActivityCount = 0

    private inline fun safe(step: String, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            Log.e("GuideStreamTVApp", "Startup step '$step' failed: ${t.message}", t)
        }
    }
}
