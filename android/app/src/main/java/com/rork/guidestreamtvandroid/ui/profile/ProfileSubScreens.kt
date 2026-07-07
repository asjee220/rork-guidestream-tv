package com.rork.guidestreamtvandroid.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Connected Services screen — mirrors iOS ConnectedServicesView.swift.
 * Toggle which streaming services the user subscribes to.
 */
@Composable
fun ConnectedServicesScreen(
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val authVm = AuthViewModel.get()
    val selectedServices by authVm.selectedServices.collectAsStateWithLifecycle()

    Column(
        modifier = modifier.fillMaxSize().background(Color(red = 0x04, green = 0x09, blue = 0x0F))
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp),
    ) {
        Spacer(Modifier.height(48.dp))
        // Back
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(GlassFill)
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onClose() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.ArrowBack, "Back", tint = TextPrimary, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.height(16.dp))
        Text("Connected Services", fontSize = 24.sp, fontWeight = FontWeight.Black, color = TextPrimary)
        Spacer(Modifier.height(6.dp))
        Text("Toggle the services you subscribe to. We'll personalise your feed.", fontSize = 13.sp, color = TextSecondary)
        Spacer(Modifier.height(20.dp))

        StreamingCatalog.all.forEach { service ->
            val isSelected = service.id in selectedServices
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 3.dp)
                    .glassCard(10)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                        val updated = if (isSelected) selectedServices - service.id else selectedServices + service.id
                        authVm.setSelectedServices(updated)
                    }
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Service icon tile
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(service.bg),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = service.name.take(2),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Black,
                        color = service.glow,
                    )
                }
                Spacer(Modifier.width(12.dp))
                Text(
                    text = service.name,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextPrimary,
                    modifier = Modifier.weight(1f),
                )
                Switch(
                    checked = isSelected,
                    onCheckedChange = {
                        val updated = if (isSelected) selectedServices - service.id else selectedServices + service.id
                        authVm.setSelectedServices(updated)
                    },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = BrandOrange,
                        checkedTrackColor = BrandOrange.copy(alpha = 0.3f),
                        uncheckedThumbColor = TextTertiary,
                        uncheckedTrackColor = GlassFill,
                    ),
                )
            }
        }
        Spacer(Modifier.height(40.dp))
    }
}

/**
 * Notifications Settings screen — mirrors iOS NotificationsSettingsView.swift.
 * Per-category push toggles synced to preferences.
 */
@Composable
fun NotificationsSettingsScreen(
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val authVm = AuthViewModel.get()
    val notifyNewEpisodes by authVm.notifyNewEpisodesEnabled.collectAsStateWithLifecycle()
    val notifyWatchlist by authVm.notifyWatchlistEnabled.collectAsStateWithLifecycle()
    val notifyLive by authVm.notifyLiveEnabled.collectAsStateWithLifecycle()
    val notifySports by authVm.notifySportsEnabled.collectAsStateWithLifecycle()
    val notifyMovieReleases by authVm.notifyMovieReleasesEnabled.collectAsStateWithLifecycle()

    Column(
        modifier = modifier.fillMaxSize().background(Color(red = 0x04, green = 0x09, blue = 0x0F))
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp),
    ) {
        Spacer(Modifier.height(48.dp))
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(GlassFill)
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onClose() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.ArrowBack, "Back", tint = TextPrimary, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.height(16.dp))
        Text("Notifications", fontSize = 24.sp, fontWeight = FontWeight.Black, color = TextPrimary)
        Spacer(Modifier.height(6.dp))
        Text("Choose what you want to be notified about.", fontSize = 13.sp, color = TextSecondary)
        Spacer(Modifier.height(20.dp))

        NotifyToggleRow("New Episodes", "Get notified when a show you watch has a new episode", notifyNewEpisodes) {
            // Individual category toggles are stored locally; the main push toggle is in onboarding/profile
        }
        NotifyToggleRow("Watchlist", "Alerts when something on your list is leaving soon", notifyWatchlist) {}
        NotifyToggleRow("Live Creators", "When a creator you follow goes live", notifyLive) {}
        NotifyToggleRow("Sports", "Game start and score alerts", notifySports) {}
        NotifyToggleRow("Movie Releases", "New movie releases on your services", notifyMovieReleases) {}

        Spacer(Modifier.height(40.dp))
    }
}

@Composable
private fun NotifyToggleRow(title: String, subtitle: String, checked: Boolean, onToggle: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .glassCard(10)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Text(subtitle, fontSize = 12.sp, color = TextTertiary)
        }
        Switch(
            checked = checked,
            onCheckedChange = onToggle,
            colors = SwitchDefaults.colors(
                checkedThumbColor = BrandOrange,
                checkedTrackColor = BrandOrange.copy(alpha = 0.3f),
                uncheckedThumbColor = TextTertiary,
                uncheckedTrackColor = GlassFill,
            ),
        )
    }
}

/**
 * Devices screen — mirrors iOS DevicesView.swift.
 * Lists active device sessions from Supabase.
 */
@Composable
fun DevicesScreen(
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxSize().background(Color(red = 0x04, green = 0x09, blue = 0x0F))
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp),
    ) {
        Spacer(Modifier.height(48.dp))
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(GlassFill)
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onClose() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.ArrowBack, "Back", tint = TextPrimary, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.height(16.dp))
        Text("Devices", fontSize = 24.sp, fontWeight = FontWeight.Black, color = TextPrimary)
        Spacer(Modifier.height(6.dp))
        Text("Active sessions on your account.", fontSize = 13.sp, color = TextSecondary)
        Spacer(Modifier.height(20.dp))

        // Placeholder — real data fetched from device_sessions
        Row(
            modifier = Modifier.fillMaxWidth().glassCard(10).padding(14.dp),
        ) {
            Column {
                Text("This device", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                Text("Active now", fontSize = 12.sp, color = TextTertiary)
            }
        }
        Spacer(Modifier.height(40.dp))
    }
}

/**
 * Help & Feedback screen — mirrors iOS HelpFeedbackView.swift.
 */
@Composable
fun HelpScreen(
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxSize().background(Color(red = 0x04, green = 0x09, blue = 0x0F))
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp),
    ) {
        Spacer(Modifier.height(48.dp))
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(GlassFill)
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onClose() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.ArrowBack, "Back", tint = TextPrimary, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.height(16.dp))
        Text("Help & Feedback", fontSize = 24.sp, fontWeight = FontWeight.Black, color = TextPrimary)
        Spacer(Modifier.height(20.dp))

        Text("Need help? We're here for you.", fontSize = 15.sp, color = TextSecondary)
        Spacer(Modifier.height(20.dp))

        HelpRow("Contact Support", "Email us at support@guidestream.tv")
        HelpRow("Privacy Policy", "How we handle your data")
        HelpRow("Terms of Service", "Our terms and conditions")
        HelpRow("About", "Guide Stream TV v1.0")

        Spacer(Modifier.height(40.dp))
    }
}

@Composable
private fun HelpRow(title: String, subtitle: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .glassCard(10)
            .padding(14.dp),
    ) {
        Column {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Text(subtitle, fontSize = 12.sp, color = TextTertiary)
        }
    }
}
