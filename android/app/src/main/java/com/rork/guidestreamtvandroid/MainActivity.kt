package com.rork.guidestreamtvandroid

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import android.util.Log
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.data.remote.RemoteConfigService
import com.rork.guidestreamtvandroid.data.repository.AppUpdateGate
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.PushTokenManager
import com.rork.guidestreamtvandroid.data.repository.ReviewPromptManager
import com.rork.guidestreamtvandroid.data.repository.SportsLiveScoreController
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import io.github.jan.supabase.auth.handleDeeplinks
import com.rork.guidestreamtvandroid.ui.ads.AdManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import com.rork.guidestreamtvandroid.ui.navigation.AppRouter
import com.rork.guidestreamtvandroid.ui.navigation.MainScreen
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.onboarding.OnboardingFlow
import com.rork.guidestreamtvandroid.ui.theme.AppTheme
import com.rork.guidestreamtvandroid.ui.theme.BrandBackground
import com.rork.guidestreamtvandroid.ui.theme.BrandWordmark
import com.rork.guidestreamtvandroid.ui.theme.SurfaceContainer
import com.rork.guidestreamtvandroid.ui.theme.WordmarkSize

class MainActivity : ComponentActivity() {

    /**
     * Notification permission launcher. Declared as a field so it is
     * registered during activity initialization — registering lazily inside
     * a composable or callback after the activity has started would throw.
     * On grant, push registration runs immediately so the first token upsert
     * happens in the same session the user allowed notifications.
     */
    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        try {
            if (granted) {
                PushTokenManager.get().registerIfPermitted()
            }
        } catch (t: Throwable) {
            Log.w("GSPush", "post-grant push registration failed: ${t.message}")
        }
    }

    /** Background scope for the deferred UMP-consent → AdMob startup step. */
    private val adConsentScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Lock phones to portrait; let tablets (>= 600dp smallest width) rotate
        // freely while still honoring the system auto-rotate lock.
        requestedOrientation = if (resources.configuration.smallestScreenWidthDp >= 600) {
            ActivityInfo.SCREEN_ORIENTATION_FULL_USER
        } else {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }

        // Import any Supabase OAuth session returned via the guidestream:// redirect.
        SupabaseManager.client.handleDeeplinks(intent) {
            AuthViewModel.get().handleOAuthCallback()
        }
        // Detect a password-recovery callback so the app can present the
        // set-new-password screen. handleDeeplinks already imported the
        // session above; we only flag the UI when the redirect URL carries
        // the flow=recovery query item (added in sendPasswordReset). Non-
        // recovery OAuth callbacks (no flow item) and title/show/sports
        // deep links keep their existing behavior.
        if (intent.data?.getQueryParameter("flow") == "recovery") {
            AuthViewModel.get().setShowPasswordRecovery(true)
        }

        // Explicit dark system-bar styles: the app is permanently dark-themed,
        // but SystemBarStyle.auto (the enableEdgeToEdge default) follows the
        // device uiMode, so a light-mode device got a white navigation-bar
        // scrim with dark icons. SystemBarStyle.dark also disables navigation
        // bar contrast enforcement — the only lever at targetSdk 36, where
        // window.navigationBarColor is a no-op. The bar color itself is
        // painted by the app inside the navigation bar inset (see RootContent).
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        setContent {
            AppTheme {
                RootContent(
                    onLaunchIntent = { handleNotificationIntent(it) },
                    initialIntent = intent,
                )
            }
        }

        // Request notification permission at launch — but only for users who
        // have already completed onboarding. New installs let the onboarding
        // notify step own the ask; updates and reinstalls (which skip
        // onboarding) are still caught here so they are not silently unable
        // to receive notifications.
        val prefs = getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)
        val hasCompletedOnboarding = prefs.getBoolean("gs.onboardingComplete", false)
        if (hasCompletedOnboarding) {
            requestNotificationPermissionIfNeeded()
        }

        // Gather UMP ad consent (EEA/UK users see the Google consent form
        // before any ad request), then initialize AdMob only when consent
        // allows ad requests. Remote config is awaited first with the same
        // 2s safety timeout the old Application AdMob block used, so the
        // first request uses the remote ad unit id when available.
        adConsentScope.launch {
            withTimeoutOrNull(2000L) {
                RemoteConfigService.load()
            }
            // GUI-43: version floor, update nudge and release notes. Evaluated
            // after the load so a first launch on a new install sees fresh
            // config; on every later launch the cached row has already
            // hydrated the same values in Application.onCreate.
            withContext(Dispatchers.Main) {
                AppUpdateGate.get().evaluate()
            }
            withContext(Dispatchers.Main) {
                AdManager.get().gatherConsentThenInitialize(this@MainActivity)
            }
        }
    }

    /**
     * On Android 13+ (Tiramisu), checks POST_NOTIFICATIONS and shows the
     * system dialog at most once per process; if already granted, refreshes
     * push registration directly. On Android 12 and below the permission
     * does not exist, so this only refreshes registration. Never crashes or
     * blocks the activity.
     */
    private fun requestNotificationPermissionIfNeeded() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val granted = ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS,
                ) == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    PushTokenManager.get().registerIfPermitted()
                } else if (!notificationPermissionRequestedThisProcess) {
                    // Guard: request at most once per process so a denial is
                    // never followed by a re-prompt loop within the session.
                    notificationPermissionRequestedThisProcess = true
                    notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                }
            } else {
                // Permission does not exist below Android 13 — no-op prompt,
                // but still refresh registration.
                PushTokenManager.get().registerIfPermitted()
            }
        } catch (t: Throwable) {
            Log.w("GSPush", "notification permission request failed: ${t.message}")
        }
    }

    private companion object {
        /** Process-scoped guard so the system dialog is launched at most once per app launch. */
        private var notificationPermissionRequestedThisProcess = false
    }

    override fun onResume() {
        super.onResume()
        // GUI-90: in-app review gate. Only ever fires on a return to the app
        // after a qualifying action — never mid-task.
        ReviewPromptManager.maybePresent(this)
        // Refresh FCM registration whenever the app foregrounds — mirrors
        // iOS refreshRegistrationIfAuthorized on scenePhase == .active. The
        // apns_token conflict target makes repeated calls idempotent. Never
        // allowed to crash or block the activity.
        try {
            PushTokenManager.get().registerIfPermitted()
        } catch (t: Throwable) {
            Log.w("GSPush", "onResume push registration failed: ${t.message}")
        }
        // Clears a tracked-game notification left pinned by a game that
        // finished while the app was dead, and repaints it otherwise. The
        // counterpart of iOS SportsLiveActivityController.reconcile().
        lifecycleScope.launch {
            try {
                SportsLiveScoreController.init(this@MainActivity).reconcile()
            } catch (t: Throwable) {
                Log.w("GSLiveScore", "onResume reconcile failed: ${t.message}")
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        SupabaseManager.client.handleDeeplinks(intent) {
            AuthViewModel.get().handleOAuthCallback()
        }
        // Detect a password-recovery callback so the app can present the
        // set-new-password screen. The session was imported above; flag the
        // UI only when the redirect URL carries the flow=recovery query
        // item (added in sendPasswordReset). Non-recovery OAuth callbacks
        // (no flow item) take the existing handleOAuthCallback path.
        if (intent.data?.getQueryParameter("flow") == "recovery") {
            AuthViewModel.get().setShowPasswordRecovery(true)
        }
        handleNotificationIntent(intent)
    }

    /**
     * Routes a launch/resume intent that may have come from a notification tap.
     *
     * Two delivery shapes have to be handled. A tap while the app is in the
     * FOREGROUND goes through [GuideStreamFirebaseMessagingService], which sets
     * the deep link as the intent's *data* URI. A tap while the app is
     * BACKGROUNDED or killed never reaches that service at all — every push
     * sender includes an FCM `notification` block, so the system tray displays
     * the notification itself and delivers the `data` payload as intent
     * *extras*. Reading only [Intent.getData], as this used to, meant the
     * common case (backgrounded) routed nowhere: GUI-46.
     *
     * Extras are preferred over the URI because they are richer. The sports
     * payload, for instance, carries `deep_link = "guidestream://sports"` with
     * no id in the path, but a `game_id` extra that identifies the game exactly.
     */
    private fun handleNotificationIntent(intent: Intent?) {
        if (intent == null) return
        val extras = intent.extras
        val router = AppRouter.get()

        val gameId = extras?.getString("game_id")?.takeIf { it.isNotBlank() }
        if (gameId != null) {
            router.showSportsGame(gameId)
            return
        }

        val titleId = extras?.getString("title_id")?.takeIf { it.isNotBlank() }
        if (titleId != null) {
            // The tap, with the title attached — mirroring iOS's AppDelegate.
            // NOTIFICATION_OPENED, not DEEPLINK_FIRED: this opens our own
            // detail screen, and nothing has been launched on a streaming
            // service yet. That launch is logged where it happens, by the
            // detail sheet's watch button.
            WatchIntentLogger.get().log(
                WatchIntentLogger.IntentEventType.NOTIFICATION_OPENED,
                titleId = titleId,
                metadata = mapOf(
                    "source" to "push_notification",
                    "notification_type" to (extras.getString("notification_type") ?: ""),
                ),
            )
            router.showTitle(
                PendingTitleRoute(
                    titleId = titleId,
                    titleName = extras.getString("title_name"),
                    isTv = extras.getString("is_tv")?.toBooleanStrictOrNull() ?: true,
                ),
            )
            return
        }

        // Nothing usable in extras — fall back to the URI, which covers the
        // foreground path and any non-notification deep link.
        val uri = intent.data
            ?: extras?.getString("deep_link")?.takeIf { it.isNotBlank() }?.let(Uri::parse)
        handleDeepLink(uri)
    }

    private fun handleDeepLink(uri: Uri?) {
        if (uri == null) return
        val router = AppRouter.get()
        val segments = uri.pathSegments
        when {
            uri.host?.contains("title") == true || uri.host?.contains("show") == true -> {
                val titleId = segments.lastOrNull() ?: uri.getQueryParameter("id") ?: return
                val title = uri.getQueryParameter("title")
                router.showTitle(
                    PendingTitleRoute(
                        titleId = titleId,
                        titleName = title,
                        isTv = uri.getQueryParameter("isTv")?.toBoolean() ?: true,
                    ),
                )
            }
            // iOS and every push payload use `guidestream://game/{id}`; the
            // sports edge function additionally emits a bare
            // `guidestream://sports` with no id, which is only routable via the
            // game_id extra handled in handleNotificationIntent.
            uri.host == "game" || uri.host == "sports" -> {
                val gameId = segments.lastOrNull()?.takeIf { it.isNotBlank() } ?: return
                router.showSportsGame(gameId)
            }
        }
    }
}

/**
 * Root content — gates between splash → onboarding → main.
 * Mirrors iOS ContentView.swift routing logic.
 */
@Composable
private fun RootContent(
    onLaunchIntent: (Intent) -> Unit,
    initialIntent: Intent?,
) {
    val auth = AuthViewModel.get()
    val sessionRestored by auth.sessionRestored.collectAsState()
    val isSignedIn by auth.isSignedIn.collectAsState()
    val hasCompletedOnboarding by auth.hasCompletedOnboarding.collectAsState()
    val isAuthenticated by auth.isAuthenticated.collectAsState()

    // Handle a deep link or notification tap from the launch intent. Passes
    // the whole Intent, not just its data URI — a cold launch from a
    // system-tray notification carries the payload in extras only.
    LaunchedEffect(initialIntent) {
        if (initialIntent != null) onLaunchIntent(initialIntent)
    }

    Box(modifier = Modifier.fillMaxSize()) {
        BrandBackground()

        when {
            // Main app — only when signed in AND onboarding complete
            isSignedIn && hasCompletedOnboarding -> {
                MainScreen(
                    router = AppRouter.get(),
                    onOpenAsk = {
                        // Ask sheet is now handled inside MainScreen via tab intercept
                    },
                )
            }
            // Session restored — run onboarding (resume at services for authed users)
            sessionRestored -> {
                OnboardingFlow(
                    startStep = if (isAuthenticated) 1 else 0,
                    onFinish = {
                        // After onboarding completes, refresh data
                        StreamsViewModel.get().refreshAll()
                    },
                )
            }
            // Still restoring session — show splash
            else -> {
                SplashScreen()
            }
        }

        // Fills the system navigation bar inset with the same SurfaceContainer
        // fill the FloatingTabBar pill uses. windowInsetsBottomHeight collapses
        // it to zero height automatically when the navigation bar is hidden
        // (Reels immersive landscape) or moves to a side edge.
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .windowInsetsBottomHeight(WindowInsets.navigationBars)
                .background(SurfaceContainer),
        )
    }
}

@Composable
private fun SplashScreen() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        BrandWordmark(size = WordmarkSize.LARGE)
    }
}
