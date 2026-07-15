package com.rork.guidestreamtvandroid.ui.profile

import android.content.Intent
import android.net.Uri
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
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Devices
import androidx.compose.material.icons.filled.Help
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Subscriptions
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.BuildConfig
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.theme.BottomSafeSpacer
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Profile screen — mirrors iOS ProfileView.swift.
 * Avatar (initials), display name, stats, menu rows.
 */
@Composable
fun ProfileScreen(
    modifier: Modifier = Modifier,
) {
    val authVm = AuthViewModel.get()
    val streamsVm = StreamsViewModel.get()
    val context = LocalContext.current

    val currentUser by authVm.currentUser.collectAsStateWithLifecycle()
    val displayName by authVm.displayName.collectAsStateWithLifecycle()
    val firstName by authVm.firstName.collectAsStateWithLifecycle()
    val lastName by authVm.lastName.collectAsStateWithLifecycle()
    val isAuthenticated by authVm.isAuthenticated.collectAsStateWithLifecycle()
    val isGuest by authVm.isGuest.collectAsStateWithLifecycle()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val newEpisodes by streamsVm.newEpisodes.collectAsStateWithLifecycle()

    var showAccount by remember { mutableStateOf(false) }
    var showConnected by remember { mutableStateOf(false) }
    var showNotifications by remember { mutableStateOf(false) }
    var showDevices by remember { mutableStateOf(false) }
    var showHelp by remember { mutableStateOf(false) }
    var showSignOutConfirm by remember { mutableStateOf(false) }

    val initials = remember(firstName, lastName, displayName, isGuest, isAuthenticated) {
        computeInitials(firstName, lastName, displayName, isGuest, isAuthenticated)
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp),
    ) {
        Spacer(Modifier.height(56.dp))

        // Header
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Avatar
            Box(
                modifier = Modifier
                    .size(88.dp)
                    .clip(CircleShape)
                    .background(BrandOrange.copy(alpha = 0.2f))
                    .border(2.dp, BrandOrange, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = initials,
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Black,
                    color = BrandOrange,
                )
            }
            Spacer(Modifier.height(12.dp))
            Text(
                text = displayName ?: (if (isGuest) "Guest" else "Welcome"),
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            if (currentUser?.email != null) {
                Spacer(Modifier.height(2.dp))
                Text(
                    text = currentUser!!.email!!,
                    fontSize = 13.sp,
                    color = TextSecondary,
                )
            }
        }

        Spacer(Modifier.height(20.dp))

        // Stats row
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            StatTile(count = userStreams.size, label = "Watching")
            StatTile(count = newEpisodes.size, label = "New Episodes")
            StatTile(count = userStreams.count { it.titleId.startsWith("yt:") || it.titleId.startsWith("tw:") || it.titleId.startsWith("pod:") }, label = "Following")
        }

        Spacer(Modifier.height(24.dp))

        // Menu rows
        if (isAuthenticated) {
            ProfileRow(
                icon = Icons.Filled.Person,
                iconTint = BrandOrange,
                title = "Account",
                subtitle = "Edit name, email, password",
                onClick = { showAccount = true },
            )
        }

        ProfileRow(
            icon = Icons.Filled.Subscriptions,
            iconTint = BrandOrange,
            title = "Connected Services",
            subtitle = "Manage streaming subscriptions",
            onClick = { showConnected = true },
        )

        ProfileRow(
            icon = Icons.Filled.Notifications,
            iconTint = BrandOrange,
            title = "Notifications",
            subtitle = "Push preferences",
            onClick = { showNotifications = true },
        )

        ProfileRow(
            icon = Icons.Filled.Devices,
            iconTint = BrandOrange,
            title = "Devices",
            subtitle = "Active sessions",
            onClick = { showDevices = true },
        )

        ProfileRow(
            icon = Icons.Filled.Help,
            iconTint = BrandOrange,
            title = "Help & Feedback",
            subtitle = "Support, diagnostics",
            onClick = { showHelp = true },
        )

        Spacer(Modifier.height(16.dp))

        // Sign out
        ProfileRow(
            icon = Icons.Filled.Logout,
            iconTint = Color(0xFFE55050),
            title = "Sign Out",
            subtitle = if (isGuest) "Exit guest mode" else "Sign out of your account",
            onClick = { showSignOutConfirm = true },
            titleColor = Color(0xFFE55050),
        )

        Spacer(Modifier.height(16.dp))

        Text(
            text = "Version ${BuildConfig.VERSION_NAME} (Build ${BuildConfig.VERSION_CODE})",
            fontSize = 12.sp,
            color = TextTertiary,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )

        BottomSafeSpacer(withTabBar = true)
    }

    // Sub-screens as overlays
    if (showAccount) {
        AccountScreen(onClose = { showAccount = false })
    }
    if (showConnected) {
        ConnectedServicesScreen(onClose = { showConnected = false })
    }
    if (showNotifications) {
        NotificationsSettingsScreen(onClose = { showNotifications = false })
    }
    if (showDevices) {
        DevicesScreen(onClose = { showDevices = false })
    }
    if (showHelp) {
        HelpScreen(onClose = { showHelp = false })
    }
    if (showSignOutConfirm) {
        SignOutConfirm(
            isGuest = isGuest,
            onConfirm = {
                showSignOutConfirm = false
                authVm.signOut()
            },
            onDismiss = { showSignOutConfirm = false },
        )
    }
}

private fun computeInitials(
    firstName: String?,
    lastName: String?,
    displayName: String?,
    isGuest: Boolean,
    isAuthenticated: Boolean,
): String {
    if (isGuest && !isAuthenticated) return "G"
    val first = firstName?.trim()?.firstOrNull()?.uppercaseChar()
    val last = lastName?.trim()?.firstOrNull()?.uppercaseChar()
    if (first != null && last != null) return "$first$last"
    if (first != null) return first.toString()
    val name = displayName?.trim()
    if (!name.isNullOrEmpty()) {
        val parts = name.split(Regex("\\s+"))
        if (parts.size >= 2) {
            return "${parts[0].first()?.uppercaseChar()}${parts[1].first()?.uppercaseChar()}"
        }
        return name.first().uppercaseChar().toString()
    }
    return "?"
}

@Composable
private fun StatTile(count: Int, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = count.toString(),
            fontSize = 24.sp,
            fontWeight = FontWeight.Black,
            color = TextPrimary,
        )
        Text(
            text = label,
            fontSize = 11.sp,
            color = TextSecondary,
        )
    }
}

@Composable
private fun ProfileRow(
    icon: ImageVector,
    iconTint: Color,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    titleColor: Color = TextPrimary,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .glassCard()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(38.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(iconTint.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = iconTint,
                modifier = Modifier.size(20.dp),
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = titleColor,
            )
            Text(
                text = subtitle,
                fontSize = 12.sp,
                color = TextTertiary,
            )
        }
        Icon(
            imageVector = Icons.Filled.ChevronRight,
            contentDescription = null,
            tint = TextTertiary,
            modifier = Modifier.size(20.dp),
        )
    }
}

@Composable
private fun SignOutConfirm(
    isGuest: Boolean,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.7f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onDismiss() },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .padding(horizontal = 32.dp)
                .glassCard()
                .padding(24.dp),
        ) {
            Text(
                text = if (isGuest) "Exit Guest Mode?" else "Sign Out?",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = if (isGuest) "Your guest data will be cleared." else "You'll need to sign in again to access your watchlist.",
                fontSize = 14.sp,
                color = TextSecondary,
            )
            Spacer(Modifier.height(20.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(12.dp))
                        .background(GlassFill)
                        .border(1.dp, GlassStroke, RoundedCornerShape(12.dp))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onDismiss() }
                        .padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("Cancel", fontSize = 14.sp, color = TextPrimary)
                }
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color(0xFFE55050))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onConfirm() }
                        .padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = if (isGuest) "Exit" else "Sign Out",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                }
            }
        }
    }
}
