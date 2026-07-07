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
import androidx.compose.material.icons.filled.Cast
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Router
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Cast to TV sheet — mirrors iOS CastToTVSheet.swift.
 * v1: troubleshooting UI with Android-appropriate intents.
 * Full Google Cast SDK integration can be a follow-up.
 */
@Composable
fun CastToTVSheet(
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var manualEntry by remember { mutableStateOf("") }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.85f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClose() },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .padding(horizontal = 20.dp)
                .glassCard(20)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { /* swallow click */ }
                .padding(20.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Filled.Cast,
                    contentDescription = "Cast",
                    tint = BrandOrange,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(Modifier.width(10.dp))
                Text(
                    text = "Cast to TV",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = TextPrimary,
                    modifier = Modifier.weight(1f),
                )
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
            }

            Spacer(Modifier.height(16.dp))

            // Scanning status
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(10.dp)
                        .clip(CircleShape)
                        .background(BrandOrange),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = "Scanning for nearby devices…",
                    fontSize = 14.sp,
                    color = TextSecondary,
                )
            }

            Spacer(Modifier.height(16.dp))

            // No devices found hint
            Text(
                text = "No cast devices found. Make sure your TV and phone are on the same Wi-Fi network.",
                fontSize = 13.sp,
                color = TextTertiary,
                lineHeight = 18.sp,
            )

            Spacer(Modifier.height(20.dp))

            // Open Settings button
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

            // Open Wi-Fi settings
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

            // Manual entry
            Text(
                text = "Manual IP Entry",
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "Enter your TV's IP address if it isn't auto-discovered.",
                fontSize = 12.sp,
                color = TextTertiary,
            )
            Spacer(Modifier.height(10.dp))

            // IP entry row
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
                    if (manualEntry.isEmpty()) {
                        Text(
                            text = "e.g. 192.168.1.100",
                            fontSize = 14.sp,
                            color = TextTertiary,
                        )
                    }
                    androidx.compose.foundation.text.BasicTextField(
                        value = manualEntry,
                        onValueChange = { manualEntry = it },
                        textStyle = androidx.compose.ui.text.TextStyle(
                            color = TextPrimary,
                            fontSize = 14.sp,
                        ),
                        cursorBrush = androidx.compose.ui.graphics.SolidColor(BrandOrange),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            Spacer(Modifier.height(20.dp))

            // Router tip
            Row(
                modifier = Modifier.fillMaxWidth(),
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

@Composable
private fun CastActionRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
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
