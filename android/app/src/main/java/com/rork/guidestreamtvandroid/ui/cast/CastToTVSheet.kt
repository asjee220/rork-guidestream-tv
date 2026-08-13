package com.rork.guidestreamtvandroid.ui.cast

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Router
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.remote.DiscoveredTvDevice
import com.rork.guidestreamtvandroid.data.remote.RokuEcpClient
import com.rork.guidestreamtvandroid.data.remote.TvCastDiscovery
import com.rork.guidestreamtvandroid.data.remote.WatchmodeSrc
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.GsSheetDragHandle
import com.rork.guidestreamtvandroid.ui.components.GsSheetHeader
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.SheetLevel
import com.rork.guidestreamtvandroid.ui.theme.SheetSurfaceRaised
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import com.rork.guidestreamtvandroid.ui.theme.sheetTopInset
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Play on TV sheet — mirrors iOS CastToTVSheet.swift.
 *
 * Roku-only discovery: scans the local /24 subnet for Roku ECP devices,
 * shows them in a list, and on tap checks ECP status, launches the correct
 * channel, shows a "Playing on" confirmation, then opens the Roku Remote app.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CastToTVSheet(
    onClose: () -> Unit,
    showTitle: String,
    platform: String,
    tmdbId: Int?,
    isTV: Boolean,
    watchmodeSource: WatchmodeSrc?,
    episodeRokuUrl: String? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()

    val discovery = remember { TvCastDiscovery() }
    val devices by discovery.devices.collectAsStateWithLifecycle()
    val isScanning by discovery.isScanning.collectAsStateWithLifecycle()
    val localIpv4 by discovery.localIpv4.collectAsStateWithLifecycle()

    var launchingDeviceId by remember { mutableStateOf<String?>(null) }
    var playingOnDevice by remember { mutableStateOf<String?>(null) }
    var limitedModeDevice by remember { mutableStateOf<DiscoveredTvDevice?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var manualHost by remember { mutableStateOf("") }
    var isProbingManual by remember { mutableStateOf(false) }
    var manualProbeError by remember { mutableStateOf(false) }

    DisposableEffect(Unit) {
        discovery.start()
        onDispose { discovery.stop() }
    }

    val phoneOnLinkLocal = localIpv4?.startsWith("169.254.") == true

    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = sheetState,
        containerColor = SheetSurfaceRaised,
        scrimColor = Color.Black.copy(alpha = 0.60f),
        tonalElevation = 0.dp,
        dragHandle = { GsSheetDragHandle(level = SheetLevel.Raised) },
        contentWindowInsets = { sheetTopInset() },
        modifier = modifier,
    ) {
        if (limitedModeDevice != null) {
            LimitedModeContent(
                device = limitedModeDevice!!,
                onRescan = {
                    limitedModeDevice = null
                    errorMessage = null
                    discovery.stop()
                    discovery.start()
                },
            )
        } else {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .navigationBarsPadding()
                    .padding(bottom = 20.dp),
            ) {
                GsSheetHeader(
                    title = "Play on TV",
                    subtitle = if (isScanning && devices.isEmpty())
                        "Scanning your network\u2026"
                    else
                        "Choose a device to send \"$showTitle\"",
                    trailing = {
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(GlassFill)
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) { onClose() },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Close,
                                contentDescription = "Close",
                                tint = TextSecondary,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                    },
                )

                Text(
                    text = "Play on TV currently supports Roku devices. Support for more TV platforms is coming in a future update.",
                    fontSize = 12.sp,
                    color = TextTertiary,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp),
                )

                Spacer(Modifier.height(8.dp))

                // Playing on banner
                if (playingOnDevice != null) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 8.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color.Black.copy(alpha = 0.5f))
                            .padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Check,
                            contentDescription = null,
                            tint = Color(0xFF3DE06A),
                            modifier = Modifier.size(22.dp),
                        )
                        Spacer(Modifier.width(10.dp))
                        Column {
                            Text(
                                text = "Playing on",
                                fontSize = 11.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = TextSecondary,
                            )
                            Text(
                                text = playingOnDevice!!,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                color = TextPrimary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }

                // Error message
                if (errorMessage != null) {
                    Text(
                        text = errorMessage!!,
                        fontSize = 13.sp,
                        color = BrandOrange,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp),
                    )
                }

                // Device list or empty state
                if (devices.isNotEmpty()) {
                    devices.forEach { device ->
                        DeviceRow(
                            device = device,
                            isLaunching = launchingDeviceId == device.id,
                            onClick = {
                                if (launchingDeviceId != null) return@DeviceRow
                                handleDeviceTap(
                                    device = device,
                                    platform = platform,
                                    tmdbId = tmdbId,
                                    isTV = isTV,
                                    watchmodeSource = watchmodeSource,
                                    episodeRokuUrl = episodeRokuUrl,
                                    showTitle = showTitle,
                                    context = context,
                                    scope = scope,
                                    onLaunchStart = { launchingDeviceId = device.id; errorMessage = null },
                                    onLimitedMode = { launchingDeviceId = null; limitedModeDevice = device },
                                    onError = { launchingDeviceId = null; errorMessage = it },
                                    onPlaying = { playingOnDevice = it },
                                    onDismissPlaying = { playingOnDevice = null },
                                    onCloseSheet = onClose,
                                )
                            },
                        )
                    }
                } else if (isScanning) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 24.dp),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CircularProgressIndicator(
                            color = BrandOrange,
                            strokeWidth = 2.dp,
                            modifier = Modifier.size(20.dp),
                        )
                        Spacer(Modifier.width(10.dp))
                        Text(
                            text = "Looking for Roku devices\u2026",
                            fontSize = 14.sp,
                            color = TextSecondary,
                        )
                    }
                } else if (phoneOnLinkLocal) {
                    Text(
                        text = "Your phone isn't on the Wi-Fi network",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextPrimary,
                        modifier = Modifier.padding(horizontal = 20.dp),
                    )
                    Text(
                        text = "Phone has a self-assigned address ($localIpv4) because the router didn't give it a real one. Connect to Wi-Fi, then rescan.",
                        fontSize = 13.sp,
                        color = TextTertiary,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp),
                    )
                } else if (localIpv4 == null && !isScanning) {
                    Text(
                        text = "Wi-Fi appears to be off",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextPrimary,
                        modifier = Modifier.padding(horizontal = 20.dp),
                    )
                    Text(
                        text = "Connect your phone to the same Wi-Fi network as your Roku device, then rescan.",
                        fontSize = 13.sp,
                        color = TextTertiary,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp),
                    )
                } else {
                    Text(
                        text = "No Roku devices found. Make sure your phone and TV are on the same Wi-Fi network.",
                        fontSize = 13.sp,
                        color = TextTertiary,
                        lineHeight = 18.sp,
                        modifier = Modifier.padding(horizontal = 20.dp),
                    )
                }

                Spacer(Modifier.height(16.dp))

                // Settings rows
                CastActionRow(
                    icon = Icons.Filled.Settings,
                    title = "Open App Settings",
                    subtitle = "Check permissions and network access",
                    onClick = {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", context.packageName, null)
                        }
                        context.startActivity(intent)
                    },
                )

                Spacer(Modifier.height(8.dp))

                CastActionRow(
                    icon = Icons.Filled.Wifi,
                    title = "Open Wi-Fi Settings",
                    subtitle = "Ensure same network as your TV",
                    onClick = {
                        val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                        context.startActivity(intent)
                    },
                )

                Spacer(Modifier.height(20.dp))

                // Manual IP entry
                ManualIpEntry(
                    manualHost = manualHost,
                    onManualHostChange = { manualHost = it },
                    isProbing = isProbingManual,
                    hasError = manualProbeError,
                    onSubmit = {
                        if (isProbingManual) return@ManualIpEntry
                        val host = manualHost.trim()
                        if (host.isEmpty()) return@ManualIpEntry
                        manualProbeError = false
                        isProbingManual = true
                        scope.launch {
                            val ok = discovery.probeManualHost(host)
                            isProbingManual = false
                            if (ok) {
                                manualHost = ""
                            } else {
                                manualProbeError = true
                            }
                        }
                    },
                )

                Spacer(Modifier.height(20.dp))

                // Router tip
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Router,
                        contentDescription = null,
                        tint = TextTertiary,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = "Tip: Some routers isolate devices. Disable AP isolation if casting fails.",
                        fontSize = 11.sp,
                        color = TextTertiary,
                        lineHeight = 15.sp,
                    )
                }
            }
        }
    }
}

// MARK: - Device row

@Composable
private fun DeviceRow(
    device: DiscoveredTvDevice,
    isLaunching: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(GlassFill)
            .border(1.dp, GlassStroke, RoundedCornerShape(14.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                enabled = !isLaunching,
            ) { onClick() }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(Color(0xFF662D91).copy(alpha = 0.35f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.Router,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(18.dp),
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = device.name,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = if (isLaunching) "Connecting\u2026" else "Roku",
                fontSize = 12.sp,
                color = TextSecondary,
            )
        }
        if (isLaunching) {
            CircularProgressIndicator(
                color = BrandOrange,
                strokeWidth = 2.dp,
                modifier = Modifier.size(20.dp),
            )
        } else if (device.host != null) {
            Text(
                text = device.host,
                fontSize = 12.sp,
                color = TextTertiary,
            )
        }
    }
}

// MARK: - Manual IP entry

@Composable
private fun ManualIpEntry(
    manualHost: String,
    onManualHostChange: (String) -> Unit,
    isProbing: Boolean,
    hasError: Boolean,
    onSubmit: () -> Unit,
) {
    Column(modifier = Modifier.padding(horizontal = 20.dp)) {
        Text(
            text = "Add device by IP",
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextPrimary,
        )
        Spacer(Modifier.height(6.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(10.dp))
                    .background(GlassFill)
                    .border(1.dp, GlassStroke, RoundedCornerShape(10.dp))
                    .padding(horizontal = 12.dp, vertical = 12.dp),
            ) {
                if (manualHost.isEmpty()) {
                    Text(
                        text = "e.g. 192.168.1.42",
                        fontSize = 14.sp,
                        color = TextTertiary,
                    )
                }
                androidx.compose.foundation.text.BasicTextField(
                    value = manualHost,
                    onValueChange = onManualHostChange,
                    textStyle = androidx.compose.ui.text.TextStyle(
                        color = TextPrimary,
                        fontSize = 14.sp,
                    ),
                    cursorBrush = androidx.compose.ui.graphics.SolidColor(BrandOrange),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Spacer(Modifier.width(8.dp))
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (manualHost.isNotBlank()) BrandOrange else GlassFill)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        enabled = !isProbing && manualHost.isNotBlank(),
                    ) { onSubmit() },
                contentAlignment = Alignment.Center,
            ) {
                if (isProbing) {
                    CircularProgressIndicator(
                        color = Color.White,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(18.dp),
                    )
                } else {
                    Icon(
                        imageVector = Icons.Filled.Check,
                        contentDescription = "Connect",
                        tint = Color.White,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
        if (hasError) {
            Spacer(Modifier.height(6.dp))
            Text(
                text = "No TV responded at that address",
                fontSize = 12.sp,
                color = BrandOrange,
            )
        }
    }
}

// MARK: - Limited mode help view

@Composable
private fun LimitedModeContent(
    device: DiscoveredTvDevice,
    onRescan: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(bottom = 20.dp),
    ) {
        // Device row (non-tappable)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(Color(0xFF662D91).copy(alpha = 0.35f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Router,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(18.dp),
                )
            }
            Spacer(Modifier.width(12.dp))
            Column {
                Text(
                    text = device.name,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextPrimary,
                )
                Text(
                    text = "Roku",
                    fontSize = 12.sp,
                    color = TextSecondary,
                )
            }
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(0.5.dp)
                .background(Color.White.copy(alpha = 0.08f)),
        )

        Text(
            text = "Device in limited mode",
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            color = TextPrimary,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 16.dp),
        )

        Text(
            text = "To let GuideStream control your Roku device:",
            fontSize = 14.sp,
            color = TextSecondary,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp),
        )

        LimitedModeStep("1", "Go to your Roku's Settings \u2192 System \u2192 Advanced system settings \u2192 Control by mobile apps")
        LimitedModeStep("2", "Select either 'Enabled' or 'Permissive'")
        LimitedModeStep("3", "Choose 'Yes, allow' when prompted")
        LimitedModeStep("4", "Press Scan again below")

        Spacer(Modifier.height(24.dp))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .height(52.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(Color(0xFF1A6FE8))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onRescan() },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "Scan again",
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
            )
        }

        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun LimitedModeStep(number: String, text: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 6.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            text = "$number.",
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextSecondary,
            modifier = Modifier.width(24.dp),
        )
        Text(
            text = text,
            fontSize = 14.sp,
            color = TextPrimary.copy(alpha = 0.85f),
        )
    }
}

// MARK: - Cast action row (kept from v1)

@Composable
private fun CastActionRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(GlassFill)
            .border(1.dp, GlassStroke, RoundedCornerShape(10.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(BrandOrange.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = BrandOrange,
                modifier = Modifier.size(18.dp),
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
            )
            Text(
                text = subtitle,
                fontSize = 12.sp,
                color = TextTertiary,
            )
        }
    }
}

// MARK: - Device tap handler

@Suppress("LongParameterList")
private fun handleDeviceTap(
    device: DiscoveredTvDevice,
    platform: String,
    tmdbId: Int?,
    isTV: Boolean,
    watchmodeSource: WatchmodeSrc?,
    episodeRokuUrl: String?,
    showTitle: String,
    context: android.content.Context,
    scope: kotlinx.coroutines.CoroutineScope,
    onLaunchStart: () -> Unit,
    onLimitedMode: () -> Unit,
    onError: (String) -> Unit,
    onPlaying: (String) -> Unit,
    onDismissPlaying: () -> Unit,
    onCloseSheet: () -> Unit,
) {
    val host = device.host
    val port = device.port
    if (host == null || port == null) {
        onError("Couldn't reach ${device.name}")
        return
    }

    onLaunchStart()

    WatchIntentLogger.get().log(
        eventType = WatchIntentLogger.IntentEventType.PLAY_ON_DEVICE_CHOSEN,
        titleId = WatchIntentLogger.get().titleSlug(showTitle),
        platformId = platform.lowercase(),
        metadata = mapOf(
            "device_id" to device.id,
            "device_kind" to "roku",
            "device_name" to device.name,
        ),
    )

    scope.launch {
        val ecpStatus = RokuEcpClient.checkEcpEnabled(host, port)

        when (ecpStatus) {
            RokuEcpClient.EcpStatus.LIMITED -> {
                onLimitedMode()
            }
            RokuEcpClient.EcpStatus.ENABLED, RokuEcpClient.EcpStatus.UNREACHABLE -> {
                // Proceed to launch — let the launch result decide
                val result = launchRoku(
                    host = host,
                    port = port,
                    platform = platform,
                    tmdbId = tmdbId,
                    isTV = isTV,
                    watchmodeSource = watchmodeSource,
                    episodeRokuUrl = episodeRokuUrl,
                )

                when (result) {
                    is RokuEcpClient.RokuLaunchResult.Ok -> {
                        onPlaying(device.name)
                        delay(1400)
                        onDismissPlaying()
                        onCloseSheet()
                        openRokuRemote(context)
                    }
                    is RokuEcpClient.RokuLaunchResult.LimitedMode -> {
                        onLimitedMode()
                    }
                    is RokuEcpClient.RokuLaunchResult.Rejected,
                    is RokuEcpClient.RokuLaunchResult.Unreachable -> {
                        val channelId = RokuEcpClient.RokuChannel.id(platform)
                        val message = if (channelId != null) {
                            "Roku didn't respond \u2014 try again"
                        } else {
                            "$platform not supported on Roku yet"
                        }
                        onError(message)
                    }
                }
            }
        }
    }
}

// MARK: - Launch helper

private suspend fun launchRoku(
    host: String,
    port: Int,
    platform: String,
    tmdbId: Int?,
    isTV: Boolean,
    watchmodeSource: WatchmodeSrc?,
    episodeRokuUrl: String?,
): RokuEcpClient.RokuLaunchResult {
    // Prefer episodeRokuUrl
    val episodePath = episodeRokuUrl?.takeIf {
        it.isNotBlank() && it.contains("launch/") &&
            !it.lowercase().contains("deeplinks available") &&
            !it.lowercase().contains("paid plan")
    }
    if (episodePath != null) {
        return RokuEcpClient.launch(host, port, episodePath)
    }

    // Then prefer watchmodeSource?.rokuUrl
    val rokuUrl = watchmodeSource?.rokuUrl?.takeIf {
        it.isNotBlank() && it.contains("launch/") &&
            !it.lowercase().contains("deeplinks available") &&
            !it.lowercase().contains("paid plan")
    }
    if (rokuUrl != null) {
        return RokuEcpClient.launch(host, port, rokuUrl)
    }

    // Otherwise: channel id + contentId
    val channelId = RokuEcpClient.RokuChannel.id(platform)
        ?: return RokuEcpClient.RokuLaunchResult.Unreachable

    val contentId = watchmodeSource?.webUrl
        ?.takeIf { it.startsWith("http") }
        ?.let { RokuEcpClient.extractContentId(it, platform) }
        ?.takeIf { it.isNotEmpty() }
        ?: tmdbId?.toString()

    val mediaType = if (isTV) "series" else "movie"

    return RokuEcpClient.launch(host, port, channelId, contentId, mediaType)
}

// MARK: - Open Roku Remote app

private fun openRokuRemote(context: android.content.Context) {
    val intents = listOf(
        Intent(Intent.ACTION_VIEW, Uri.parse("roku://")),
        Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.roku.remote")),
        Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=com.roku.remote")),
    )
    for (intent in intents) {
        if (intent.resolveActivity(context.packageManager) != null) {
            try {
                context.startActivity(intent)
                return
            } catch (_: Exception) {
                // Try next fallback
            }
        }
    }
}
