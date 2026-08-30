package com.rork.guidestreamtvandroid.ui.components

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.SystemUpdateAlt
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
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
import com.rork.guidestreamtvandroid.data.repository.AppUpdatePrompt
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.SheetSurfaceBase
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary

/**
 * The three faces of AppUpdateGate (GUI-43). Android port of iOS
 * `AppUpdateSheet`.
 *
 * A required update is a full-bleed Dialog with dismissal switched off at the
 * window level — a ModalBottomSheet can always be swiped away, and "required"
 * has to mean it. The other two are ordinary bottom sheets.
 */
@Composable
fun AppUpdateHost(prompt: AppUpdatePrompt?, onDismiss: () -> Unit) {
    if (prompt == null) return
    if (prompt is AppUpdatePrompt.Required) {
        Dialog(
            onDismissRequest = { /* required: no way out but updating */ },
            properties = DialogProperties(
                usePlatformDefaultWidth = false,
                dismissOnBackPress = false,
                dismissOnClickOutside = false,
            ),
        ) {
            Box(modifier = Modifier.fillMaxSize().background(Navy).statusBarsPadding()) {
                AppUpdateBody(prompt = prompt, onDismiss = onDismiss)
            }
        }
    } else {
        AppUpdateBottomSheet(prompt = prompt, onDismiss = onDismiss)
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun AppUpdateBottomSheet(prompt: AppUpdatePrompt, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = SheetSurfaceBase,
        dragHandle = { GsSheetDragHandle() },
    ) {
        AppUpdateBody(prompt = prompt, onDismiss = onDismiss)
    }
}

@Composable
private fun AppUpdateBody(prompt: AppUpdatePrompt, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val blocking = prompt is AppUpdatePrompt.Required

    val heading = when (prompt) {
        is AppUpdatePrompt.Required -> "Time to update"
        is AppUpdatePrompt.Available -> "A new version is ready"
        is AppUpdatePrompt.WhatsNew -> prompt.title
    }
    val subheading = when (prompt) {
        is AppUpdatePrompt.Required ->
            "This version of GuideStream can no longer talk to our servers. Update to keep watching."
        is AppUpdatePrompt.Available -> "Version ${prompt.version} is on Google Play."
        is AppUpdatePrompt.WhatsNew -> "You're on version ${prompt.version}."
    }
    val notes = when (prompt) {
        is AppUpdatePrompt.Required -> emptyList()
        is AppUpdatePrompt.Available -> prompt.notes
        is AppUpdatePrompt.WhatsNew -> prompt.notes
    }
    val primaryLabel = if (prompt is AppUpdatePrompt.WhatsNew) "Continue" else "Update"

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .padding(top = if (blocking) 40.dp else 4.dp, bottom = 28.dp),
    ) {
        if (!blocking) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.10f))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onDismiss() },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "Close",
                        tint = Color.White.copy(alpha = 0.65f),
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
        }

        Icon(
            imageVector = if (blocking) Icons.Filled.SystemUpdateAlt else Icons.Filled.AutoAwesome,
            contentDescription = null,
            tint = BrandOrange,
            modifier = Modifier.size(34.dp),
        )
        Spacer(Modifier.height(16.dp))

        Text(
            text = heading,
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            color = TextPrimary,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            text = subheading,
            fontSize = 14.sp,
            color = TextPrimary.copy(alpha = 0.6f),
            lineHeight = 20.sp,
        )

        if (notes.isNotEmpty()) {
            Spacer(Modifier.height(20.dp))
            notes.take(5).forEach { note ->
                Row(modifier = Modifier.padding(bottom = 10.dp)) {
                    Box(
                        modifier = Modifier
                            .padding(top = 7.dp, end = 10.dp)
                            .size(5.dp)
                            .clip(CircleShape)
                            .background(BrandOrange),
                    )
                    Text(
                        text = note,
                        fontSize = 15.sp,
                        color = TextPrimary.copy(alpha = 0.85f),
                        lineHeight = 21.sp,
                    )
                }
            }
        }

        Spacer(Modifier.height(24.dp))

        val storeUrl = when (prompt) {
            is AppUpdatePrompt.Required -> prompt.storeUrl
            is AppUpdatePrompt.Available -> prompt.storeUrl
            is AppUpdatePrompt.WhatsNew -> null
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp)
                .clip(CircleShape)
                .background(BrandOrange)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) {
                    if (prompt is AppUpdatePrompt.WhatsNew) {
                        onDismiss()
                    } else {
                        if (storeUrl != null) {
                            runCatching {
                                context.startActivity(
                                    Intent(Intent.ACTION_VIEW, Uri.parse(storeUrl))
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                            }
                        }
                        // A required update deliberately stays up: the user
                        // comes back through a relaunch, having actually
                        // updated.
                        if (!blocking) onDismiss()
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = primaryLabel,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
            )
        }

        if (prompt is AppUpdatePrompt.Available) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onDismiss() },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "Not now",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    color = TextPrimary.copy(alpha = 0.55f),
                )
            }
        }
    }
}
