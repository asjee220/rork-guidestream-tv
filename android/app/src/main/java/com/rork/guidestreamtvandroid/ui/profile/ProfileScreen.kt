package com.rork.guidestreamtvandroid.ui.profile

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary

/** Placeholder Profile screen — full implementation in Phase 8. */
@Composable
fun ProfileScreen(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Text("Profile", color = TextSecondary)
    }
}
