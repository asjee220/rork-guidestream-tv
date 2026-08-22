package com.rork.guidestreamtvandroid.ui.ads

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.SurfaceDark
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Full-screen inspector for the ad stack, opened from Help & Feedback.
 *
 * Mirrors the iOS Ad Diagnostics sheet so a Play testing build can explain why
 * sponsored slots are empty — consent blocked, SDK not initialized, an ad unit
 * from the wrong AdMob app, or plain no-fill — without needing logcat.
 */
@Composable
fun AdDiagnosticsDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val adManager = AdManager.get()

    var refreshTick by remember { mutableIntStateOf(0) }
    var didCopy by remember { mutableStateOf(false) }

    val diagnostics = remember(refreshTick) { adManager.diagnostics(context) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Navy)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "Ad Diagnostics",
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Black,
                    color = TextPrimary,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = "Close",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    color = BrandOrange,
                    modifier = Modifier.clickable { onDismiss() },
                )
            }

            Spacer(Modifier.height(16.dp))

            DiagnosticsCard(title = "SUMMARY") {
                Text(
                    text = diagnostics.summary,
                    fontSize = 13.sp,
                    color = TextPrimary,
                )
            }

            Spacer(Modifier.height(14.dp))

            DiagnosticsCard(title = "PIPELINE") {
                DiagnosticLine("SDK initialized", diagnostics.sdkInitialized)
                DiagnosticLine("Consent status", diagnostics.consentStatus)
                DiagnosticLine("Can request ads", diagnostics.canRequestAds)
                DiagnosticLine("Privacy options required", if (diagnostics.privacyOptionsRequired) "Yes" else "No")
            }

            Spacer(Modifier.height(14.dp))

            DiagnosticsCard(title = "AD UNITS") {
                DiagnosticLine("Manifest app id", diagnostics.manifestAppId)
                DiagnosticLine("Native unit", diagnostics.nativeAdUnitId)
                DiagnosticLine("Interstitial unit", diagnostics.interstitialAdUnitId)
                diagnostics.remoteUnitRejected?.let {
                    DiagnosticLine("Remote unit rejected", it, tint = Color(0xFFFF453A))
                }
            }

            Spacer(Modifier.height(14.dp))

            DiagnosticsCard(title = "THIS SESSION") {
                DiagnosticLine("Load attempts", diagnostics.nativeLoadAttempts.toString())
                DiagnosticLine("Ads received", diagnostics.nativeAdsReceived.toString())
                DiagnosticLine("Interstitial ready", diagnostics.interstitialReady)
                diagnostics.lastNativeError?.let {
                    DiagnosticLine("Last native error", it, tint = Color(0xFFFF453A))
                }
                diagnostics.lastInterstitialError?.let {
                    DiagnosticLine("Last interstitial error", it, tint = Color(0xFFFF453A))
                }
            }

            Spacer(Modifier.height(20.dp))

            ActionButton(
                label = "Retry ad load",
                background = BrandOrange,
                textColor = Color.White,
            ) {
                (context as? Activity)?.let { adManager.retryFromDiagnostics(it) }
                refreshTick += 1
            }

            Spacer(Modifier.height(10.dp))

            ActionButton(
                label = if (didCopy) "Copied" else "Copy report",
                background = Color.White.copy(alpha = 0.10f),
                textColor = TextPrimary,
            ) {
                copyToClipboard(context, diagnostics.plainText)
                didCopy = true
            }

            Spacer(Modifier.height(10.dp))

            ActionButton(
                label = "Refresh",
                background = Color.White.copy(alpha = 0.06f),
                textColor = TextSecondary,
            ) {
                refreshTick += 1
            }

            Spacer(Modifier.height(40.dp))
        }
    }
}

private fun copyToClipboard(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
    clipboard?.setPrimaryClip(ClipData.newPlainText("Ad Diagnostics", text))
}

@Composable
private fun DiagnosticsCard(title: String, content: @Composable () -> Unit) {
    Column {
        Text(
            text = title,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = TextTertiary,
            modifier = Modifier.padding(start = 4.dp, bottom = 6.dp),
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .background(SurfaceDark)
                .border(1.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(14.dp))
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            content()
        }
    }
}

@Composable
private fun DiagnosticLine(label: String, value: String, tint: Color? = null) {
    Row(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = label,
            fontSize = 12.sp,
            color = TextSecondary,
            modifier = Modifier.weight(1f),
        )
        Spacer(Modifier.width(10.dp))
        Text(
            text = value,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = tint ?: TextPrimary,
            modifier = Modifier.weight(1.4f),
        )
    }
}

@Composable
private fun DiagnosticLine(label: String, state: Boolean) {
    DiagnosticLine(
        label = label,
        value = if (state) "Yes" else "No",
        tint = if (state) Color(0xFF30D158) else Color(0xFFFF453A),
    )
}

@Composable
private fun ActionButton(
    label: String,
    background: Color,
    textColor: Color,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(background)
            .clickable { onClick() }
            .padding(vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold,
            color = textColor,
        )
    }
}
