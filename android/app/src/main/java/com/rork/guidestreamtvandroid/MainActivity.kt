package com.rork.guidestreamtvandroid

import android.content.Intent
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.ui.navigation.AppRouter
import com.rork.guidestreamtvandroid.ui.navigation.MainScreen
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.onboarding.EmailAuthScreen
import com.rork.guidestreamtvandroid.ui.onboarding.OnboardingFlow
import com.rork.guidestreamtvandroid.ui.theme.AppTheme
import com.rork.guidestreamtvandroid.ui.theme.BrandBackground
import com.rork.guidestreamtvandroid.ui.theme.BrandWordmark
import com.rork.guidestreamtvandroid.ui.theme.WordmarkSize

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
    var showEmailAuth by remember { mutableStateOf(false) }

    // Handle deep link from initial intent
    LaunchedEffect(initialIntent) {
        val uri = initialIntent?.data
        if (uri != null) onDeepLink(uri)
    }

    val showOnboarding = !hasCompletedOnboarding && !isAuthenticated
    val showMain = isSignedIn && (hasCompletedOnboarding || isAuthenticated)

    Box(modifier = Modifier.fillMaxSize()) {
        BrandBackground()

        when {
            // Still restoring session — show splash
            !sessionRestored && !showOnboarding -> {
                SplashScreen()
            }
            // Onboarding needed
            showOnboarding && !showEmailAuth -> {
                OnboardingFlow(
                    onFinish = {
                        // After onboarding completes, refresh data
                        StreamsViewModel.get().refreshAll()
                    },
                    onEmailAuth = { showEmailAuth = true },
                )
            }
            // Email auth sheet
            showEmailAuth -> {
                EmailAuthScreen(
                    onAuthenticated = {
                        showEmailAuth = false
                        StreamsViewModel.get().refreshAll()
                    },
                    onClose = { showEmailAuth = false },
                )
            }
            // Main app
            else -> {
                MainScreen(
                    router = AppRouter.get(),
                    onOpenAsk = {
                        // TODO: open Ask Stream sheet
                    },
                )
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
