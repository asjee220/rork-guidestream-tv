package com.rork.guidestreamtvandroid.ui.profile

import android.Manifest
import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.models.DeviceSessionRow
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.launch
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.PushTokenManager
import com.rork.guidestreamtvandroid.ui.ads.AdManager
import com.rork.guidestreamtvandroid.ui.components.NotificationPermissionState
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.data.repository.ReviewPromptManager
import com.rork.guidestreamtvandroid.ui.components.openInAppBrowser
import com.rork.guidestreamtvandroid.ui.components.markNotificationPermissionAsked
import com.rork.guidestreamtvandroid.ui.components.notificationPermissionState
import com.rork.guidestreamtvandroid.ui.components.openAppNotificationSettings
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

@Composable
private fun ServiceSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var isFocused by remember { mutableStateOf(false) }
    BasicTextField(
        value = query,
        onValueChange = onQueryChange,
        singleLine = true,
        textStyle = TextStyle(color = Color.White, fontSize = 15.sp),
        cursorBrush = SolidColor(BrandOrange),
        modifier = modifier
            .fillMaxWidth()
            .height(44.dp)
            .clip(RoundedCornerShape(50.dp))
            .background(Color.White.copy(alpha = 0.05f))
            .border(
                1.dp,
                if (isFocused) BrandOrange else Color.White.copy(alpha = 0.10f),
                RoundedCornerShape(50.dp),
            )
            .onFocusChanged { isFocused = it.isFocused },
        decorationBox = { innerTextField ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp)
                    .padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Filled.Search,
                    contentDescription = null,
                    tint = TextSecondary,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(8.dp))
                Box(modifier = Modifier.weight(1f)) {
                    if (query.isEmpty()) {
                        Text(
                            text = "Search services",
                            fontSize = 15.sp,
                            color = TextSecondary,
                        )
                    }
                    innerTextField()
                }
            }
        },
    )
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
    val context = LocalContext.current
    val notifyPush by authVm.notifyPushEnabled.collectAsStateWithLifecycle()
    val notifyNewEpisodes by authVm.notifyNewEpisodesEnabled.collectAsStateWithLifecycle()
    val notifyWatchlist by authVm.notifyWatchlistEnabled.collectAsStateWithLifecycle()
    val notifyLive by authVm.notifyLiveEnabled.collectAsStateWithLifecycle()
    val notifySports by authVm.notifySportsEnabled.collectAsStateWithLifecycle()
    val notifyMovieReleases by authVm.notifyMovieReleasesEnabled.collectAsStateWithLifecycle()

    // `notifyPush` is only the user's *intent*. The OS grant decides whether a
    // notification can actually be delivered, and on Android 13+ the two drift
    // apart: uninstalling clears POST_NOTIFICATIONS while the intent survives
    // in `users.notify_push`, so a reinstall would otherwise show the master
    // switch on while nothing could ever arrive.
    var permState by remember { mutableStateOf(notificationPermissionState(context)) }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            // Catches a grant (or revocation) made in system Settings while
            // this screen was backgrounded.
            if (event == Lifecycle.Event.ON_RESUME) {
                permState = notificationPermissionState(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        markNotificationPermissionAsked(context)
        permState = notificationPermissionState(context)
        authVm.setNotifyPushEnabled(granted)
        if (granted) PushTokenManager.get().registerIfPermitted()
    }

    val pushOn = notifyPush && permState == NotificationPermissionState.GRANTED

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

        if (notifyPush && permState == NotificationPermissionState.DENIED) {
            NotifyStatusBanner(
                title = "Notifications are off in Settings",
                message = "Android blocked notifications for GuideStream. Tap here to turn them back on.",
                onClick = { openAppNotificationSettings(context) },
            )
            Spacer(Modifier.height(10.dp))
        } else if (notifyPush && permState == NotificationPermissionState.NOT_DETERMINED) {
            NotifyStatusBanner(
                title = "Turn notifications back on",
                message = "Android clears notification permission when an app is uninstalled. " +
                    "Flip the switch below — your alert types are still saved.",
            )
            Spacer(Modifier.height(10.dp))
        }

        NotifyToggleRow(
            "Push Notifications",
            "Allow GuideStream to send you alerts",
            pushOn,
        ) { wantOn ->
            if (!wantOn) {
                authVm.setNotifyPushEnabled(false)
            } else {
                when (permState) {
                    NotificationPermissionState.GRANTED -> {
                        authVm.setNotifyPushEnabled(true)
                        PushTokenManager.get().registerIfPermitted()
                    }
                    NotificationPermissionState.NOT_DETERMINED ->
                        permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    // Android never re-shows the dialog after a denial, so send
                    // the user to Settings rather than silently clearing the
                    // intent they just expressed.
                    NotificationPermissionState.DENIED -> openAppNotificationSettings(context)
                }
            }
        }

        Spacer(Modifier.height(10.dp))

        // Category switches cannot fire while the master switch is off — dim
        // and lock them so the screen can't show five live-looking alert types
        // that will never arrive.
        Column(modifier = Modifier.alpha(if (pushOn) 1f else 0.4f)) {
            NotifyToggleRow(
                "New Episodes",
                "When shows you follow drop a new episode",
                notifyNewEpisodes,
                enabled = pushOn,
            ) { authVm.setNotifyNewEpisodesEnabled(it) }
            NotifyToggleRow(
                "Watchlist",
                "When a saved title lands on a service you have",
                notifyWatchlist,
                enabled = pushOn,
            ) { authVm.setNotifyWatchlistEnabled(it) }
            NotifyToggleRow(
                "Live Creators",
                "When a creator you follow goes live",
                notifyLive,
                enabled = pushOn,
            ) { authVm.setNotifyLiveEnabled(it) }
            NotifyToggleRow(
                "Sports",
                "Game start, live, and final scores for your teams",
                notifySports,
                enabled = pushOn,
            ) { authVm.setNotifySportsEnabled(it) }
            NotifyToggleRow(
                "Movie Releases",
                "New movie releases on your services",
                notifyMovieReleases,
                enabled = pushOn,
            ) { authVm.setNotifyMovieReleasesEnabled(it) }
        }

        Spacer(Modifier.height(40.dp))
    }
}

/** Warning banner explaining why push is off despite the saved intent. */
@Composable
private fun NotifyStatusBanner(
    title: String,
    message: String,
    onClick: (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (onClick != null) {
                    Modifier.clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onClick() }
                } else {
                    Modifier
                },
            )
            .clip(RoundedCornerShape(14.dp))
            .background(BrandOrange.copy(alpha = 0.10f))
            .border(1.dp, BrandOrange.copy(alpha = 0.30f), RoundedCornerShape(14.dp))
            .padding(14.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(
            imageVector = Icons.Filled.Warning,
            contentDescription = null,
            tint = BrandOrange,
            modifier = Modifier.size(16.dp),
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Spacer(Modifier.height(4.dp))
            Text(message, fontSize = 12.sp, color = TextSecondary)
        }
    }
}

@Composable
private fun NotifyToggleRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    enabled: Boolean = true,
    onToggle: (Boolean) -> Unit,
) {
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
            enabled = enabled,
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
    val authVm = AuthViewModel.get()
    val currentUser by authVm.currentUser.collectAsStateWithLifecycle()
    val isAuthenticated = authVm.isAuthenticated.value
    val currentDeviceId = remember { DeviceIdentity.get().deviceId }
    val scope = rememberCoroutineScope()

    var rows by remember { mutableStateOf<List<DeviceSessionRow>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var removingId by remember { mutableStateOf<String?>(null) }
    var confirmRemoveId by remember { mutableStateOf<String?>(null) }

    // ACTIVE sessions only. `device_sessions` holds one row per INSTALL, not
    // per physical device, and builds from before the device id was persisted
    // across reinstalls minted a fresh id every time — one phone can sit behind
    // a hundred rows. Listing all of them would make this a changelog of old
    // installs rather than a list of places the account is signed in.
    suspend fun load() {
        val uid = currentUser?.id ?: run {
            rows = emptyList(); isLoading = false; return
        }
        isLoading = true
        try {
            val cutoff = java.time.Instant.now()
                .minus(java.time.Duration.ofDays(ACTIVE_WINDOW_DAYS))
                .toString()
            rows = SupabaseManager.client.postgrest
                .from("device_sessions")
                .select(
                    Columns.raw(
                        "device_id, device_model, os_version, app_version, " +
                            "build_number, last_seen_at, first_seen_at, " +
                            "is_authenticated, is_guest, session_count",
                    ),
                ) {
                    filter {
                        eq("user_id", uid)
                        gte("last_seen_at", cutoff)
                    }
                    order("last_seen_at", Order.DESCENDING)
                }
                .decodeList<DeviceSessionRow>()
            loadError = null
        } catch (e: Exception) {
            loadError = e.message
        } finally {
            isLoading = false
        }
    }

    suspend fun removeDevice(deviceId: String) {
        removingId = deviceId
        try {
            // Signing out the CURRENT device is a local sign-out, not a row
            // delete — deleting our own row would just be re-created by the
            // next session upsert.
            if (deviceId == currentDeviceId) {
                authVm.signOut()
                return
            }
            SupabaseManager.client.postgrest
                .from("device_sessions")
                .delete { filter { eq("device_id", deviceId) } }
            load()
        } catch (e: Exception) {
            loadError = e.message
        } finally {
            removingId = null
        }
    }

    LaunchedEffect(currentUser?.id) { load() }

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

        when {
            !isAuthenticated -> {
                Text(
                    "Sign in to see the devices your account is signed in on.",
                    fontSize = 13.sp,
                    color = TextTertiary,
                    modifier = Modifier.fillMaxWidth().glassCard(10).padding(14.dp),
                )
            }
            isLoading && rows.isEmpty() -> {
                Box(Modifier.fillMaxWidth().height(80.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = BrandOrange, modifier = Modifier.size(28.dp))
                }
            }
            rows.isEmpty() -> {
                Text(
                    "No active sessions in the last 30 days.",
                    fontSize = 13.sp,
                    color = TextTertiary,
                    modifier = Modifier.fillMaxWidth().glassCard(10).padding(14.dp),
                )
            }
            else -> {
                Column(Modifier.fillMaxWidth().glassCard(10)) {
                    rows.forEachIndexed { index, row ->
                        if (index > 0) {
                            Box(
                                Modifier.fillMaxWidth().height(1.dp)
                                    .background(Color.White.copy(alpha = 0.06f)),
                            )
                        }
                        DeviceSessionCell(
                            row = row,
                            isCurrent = row.deviceId == currentDeviceId,
                            isRemoving = removingId == row.deviceId,
                            onRemove = { confirmRemoveId = row.deviceId },
                        )
                    }
                }
            }
        }

        loadError?.let {
            Spacer(Modifier.height(10.dp))
            Text(it, fontSize = 12.sp, color = Color(0xFFEF4444))
        }

        Spacer(Modifier.height(40.dp))
    }

    confirmRemoveId?.let { target ->
        val isCurrent = target == currentDeviceId
        AlertDialog(
            onDismissRequest = { confirmRemoveId = null },
            title = { Text(if (isCurrent) "Sign out of this device?" else "Sign this device out?") },
            text = {
                Text(
                    if (isCurrent) {
                        "You'll be signed out here and returned to browsing as a guest."
                    } else {
                        "That device will be signed out of your account the next time it opens the app."
                    },
                )
            },
            confirmButton = {
                Text(
                    text = "Sign out",
                    color = BrandOrange,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) {
                            val id = target
                            confirmRemoveId = null
                            scope.launch { removeDevice(id) }
                        }
                        .padding(12.dp),
                )
            },
            dismissButton = {
                Text(
                    text = "Cancel",
                    color = TextSecondary,
                    modifier = Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { confirmRemoveId = null }
                        .padding(12.dp),
                )
            },
        )
    }
}

/** One row in [DevicesScreen]. Mirrors the iOS DeviceCellView. */
@Composable
private fun DeviceSessionCell(
    row: DeviceSessionRow,
    isCurrent: Boolean,
    isRemoving: Boolean,
    onRemove: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = row.deviceModel?.takeIf { it.isNotBlank() } ?: "Unknown device",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextPrimary,
                )
                if (isCurrent) {
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = "This device",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = BrandOrange,
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(BrandOrange.copy(alpha = 0.15f))
                            .padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                }
            }
            Spacer(Modifier.height(2.dp))
            Text(
                text = listOfNotNull(
                    row.osVersion?.takeIf { it.isNotBlank() }?.let { "Android $it" },
                    row.appVersion?.takeIf { it.isNotBlank() }?.let { "v$it" },
                    relativeLastSeen(row.lastSeenAt),
                ).joinToString(" · "),
                fontSize = 12.sp,
                color = TextTertiary,
            )
        }
        if (isRemoving) {
            CircularProgressIndicator(color = BrandOrange, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
        } else {
            Text(
                text = "Sign out",
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = BrandOrange,
                modifier = Modifier
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onRemove() }
                    .padding(6.dp),
            )
        }
    }
}

/**
 * "Active now" / "2h ago" / "3d ago" from an ISO-8601 timestamp. Anything
 * unparseable renders as nothing rather than a wrong claim about when the
 * device was last seen.
 */
private fun relativeLastSeen(iso: String?): String? {
    val text = iso?.takeIf { it.isNotBlank() } ?: return null
    val millis = runCatching {
        java.time.Instant.parse(
            if (text.endsWith("Z") || text.contains("+")) text else text + "Z",
        ).toEpochMilli()
    }.getOrNull() ?: runCatching {
        java.time.OffsetDateTime.parse(text.replace(" ", "T")).toInstant().toEpochMilli()
    }.getOrNull() ?: return null

    val delta = System.currentTimeMillis() - millis
    return when {
        delta < 5 * 60_000L -> "Active now"
        delta < 60 * 60_000L -> "${delta / 60_000L}m ago"
        delta < 24 * 60 * 60_000L -> "${delta / (60 * 60_000L)}h ago"
        else -> "${delta / (24 * 60 * 60_000L)}d ago"
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
    // Non-null while the in-app support form is open, carrying the topic the
    // tapped row preselects (GUI-87).
    var supportTopic by remember { mutableStateOf<String?>(null) }
    if (supportTopic != null) {
        SupportFormScreen(
            presetTopic = supportTopic!!,
            onClose = { supportTopic = null },
            modifier = modifier,
        )
        return
    }

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

        // These three were rendered with no onClick at all, so they were not
        // merely broken links - they were not tappable. The URLs are the ones
        // the onboarding consent copy already links to, and both pages are
        // live. (GUI-83)
        //
        // GUI-87: the legal pages now open in a Chrome Custom Tab over the app
        // rather than task-switching to the browser, and Contact Support opens
        // the in-app form instead of handing off to a mail app.
        val helpContext = LocalContext.current
        val openUrl: (String) -> Unit = { url -> openInAppBrowser(helpContext, url) }
        HelpRow(
            "Contact Support",
            "Write to us without leaving the app",
            onClick = { supportTopic = "I have a question" },
        )
        HelpRow(
            "Report a Problem",
            "Something not working? Let us know.",
            onClick = { supportTopic = "Something is broken" },
        )
        // Opens the Play Store listing, not Play's in-app review sheet — that
        // sheet is quota'd and silently no-ops once spent, so a button wired to
        // it looks broken. The automatic prompt owns the quota.
        HelpRow(
            "Rate Guide Stream TV",
            "Tell us how we're doing on Google Play",
            onClick = { ReviewPromptManager.openStoreListing(helpContext) },
        )
        HelpRow(
            "Privacy Policy",
            "How we handle your data",
            onClick = { openUrl("https://guidestream.tv/privacy") },
        )
        HelpRow(
            "Terms of Service",
            "Our terms and conditions",
            onClick = { openUrl("https://guidestream.tv/terms") },
        )
        // Ad privacy options entry point — only rendered where UMP says one
        // is required (EEA/UK). Hidden, not disabled, elsewhere.
        val adManager = AdManager.get()
        val privacyOptionsRequired by adManager.privacyOptionsRequired.collectAsState()
        if (privacyOptionsRequired) {
            val context = LocalContext.current
            HelpRow(
                "Ad Privacy Options",
                "Manage your ad consent choices",
                onClick = {
                    (context as? Activity)?.let { adManager.showPrivacyOptions(it) }
                },
            )
        }
        // Ad Diagnostics removed (GUI-83). It was an engineering inspector for
        // why sponsored slots come back empty - consent, SDK init, ad-unit
        // mismatch, no-fill - and nothing a customer can act on.
        HelpRow("About", "Guide Stream TV v1.0")

        Spacer(Modifier.height(40.dp))
    }
}

@Composable
private fun HelpRow(title: String, subtitle: String, onClick: (() -> Unit)? = null) {
    val baseModifier = Modifier
        .fillMaxWidth()
        .padding(vertical = 3.dp)
        .glassCard(10)
    Row(
        modifier = (
            if (onClick != null) {
                baseModifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onClick() }
            } else {
                baseModifier
            }
            ).padding(14.dp),
    ) {
        Column {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Text(subtitle, fontSize = 12.sp, color = TextTertiary)
        }
    }
}

/** How recently a session must have been seen to count as active. */
private const val ACTIVE_WINDOW_DAYS = 30L
