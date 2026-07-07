package com.rork.guidestreamtvandroid.ui.sports

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary

/** Placeholder Sports screen — full implementation in Phase 7. */
@Composable
fun SportsScreen(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Text("Sports", color = TextSecondary)
    }
}
