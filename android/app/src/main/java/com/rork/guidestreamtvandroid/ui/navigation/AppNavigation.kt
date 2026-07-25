package com.rork.guidestreamtvandroid.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.ui.onboarding.UpdatePasswordScreen
import com.rork.guidestreamtvandroid.ui.screens.HomeScreen

@Composable
fun AppNavigation() {
    val navController = rememberNavController()
    val auth = AuthViewModel.get()
    val showRecovery by auth.showPasswordRecovery.collectAsState()

    Box(modifier = Modifier.fillMaxSize()) {
        NavHost(
            navController = navController,
            startDestination = "home"
        ) {
            composable("home") {
                HomeScreen()
            }
        }

        // Present the set-new-password screen over whatever is on screen
        // when a Supabase recovery callback imported a session. Clearing the
        // flag (on dismiss or success) removes the overlay and drops the
        // user into the signed-in app.
        if (showRecovery) {
            UpdatePasswordScreen(
                onDismiss = { auth.clearPasswordRecovery() },
            )
        }
    }
}
