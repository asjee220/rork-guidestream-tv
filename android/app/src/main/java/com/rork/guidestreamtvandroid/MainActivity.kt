package com.rork.guidestreamtvandroid

import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import io.github.jan.supabase.auth.handleDeeplinks
import com.rork.guidestreamtvandroid.ui.navigation.AppRouter
import com.rork.guidestreamtvandroid.ui.navigation.MainScreen
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.onboarding.OnboardingFlow
import com.rork.guidestreamtvandroid.ui.theme.AppTheme
import com.rork.guidestreamtvandroid.ui.theme.BrandBackground
import com.rork.guidestreamtvandroid.ui.theme.BrandWordmark
import com.rork.guidestreamtvandroid.ui.theme.WordmarkSize

class MainActivity : ComponentActivity() {
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
        // type=recovery. Non-recovery OAuth callbacks and title/show/sports
        // deep links keep their existing behavior.
        if (intent.dataString?.contains("type=recovery") == true) {
            AuthViewModel.get().setShowPasswordRecovery(true)
        }

        enableEdgeToEdge()
        setContent {
            AppTheme {
                RootContent(
                    onDeepLink = { handleDeepLink(it) },
                    initialIntent = intent,
                )
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
        // UI only when the redirect URL carries type=recovery.
        if (intent.dataString?.contains("type=recovery") == true) {
            AuthViewModel.get().setShowPasswordRecovery(true)
        }
        handleDeepLink(intent.data)
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
            uri.host == "sports" -> {
                val gameId = segments.lastOrNull() ?: return
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
    onDeepLink: (Uri) -> Unit,
    initialIntent: Intent?,
) {
    val auth = AuthViewModel.get()
    val sessionRestored by auth.sessionRestored.collectAsState()
    val isSignedIn by auth.isSignedIn.collectAsState()
    val hasCompletedOnboarding by auth.hasCompletedOnboarding.collectAsState()
    val isAuthenticated by auth.isAuthenticated.collectAsState()

    // Handle deep link from initial intent
    LaunchedEffect(initialIntent) {
        val uri = initialIntent?.data
        if (uri != null) onDeepLink(uri)
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
