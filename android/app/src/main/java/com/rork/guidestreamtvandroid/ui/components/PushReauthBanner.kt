package com.rork.guidestreamtvandroid.ui.components

import android.Manifest
import android.content.Context
import android.os.Build
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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.PushTokenManager
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary

private const val PREFS_NAME = "gs_prefs"
private const val DISMISSED_KEY = "gs.pushReauthBannerDismissed"

private fun bannerDismissed(context: Context): Boolean =
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getBoolean(DISMISSED_KEY, false)

private fun setBannerDismissed(context: Context) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .putBoolean(DISMISSED_KEY, true)
        .apply()
}

/**
 * Home-screen prompt shown when the account wants push
 * (`users.notify_push`, restored from the server) but POST_NOTIFICATIONS has
 * never been asked for on this install.
 *
 * GUI-41 put this message on Profile → Notifications only. That screen is
 * reached deliberately, and someone who just reinstalled — or who signed in on
 * a new phone — has no reason to go looking; they would simply stop getting
 * alerts and never find out why. Home is where they already are.
 *
 * Renders nothing when the permission is [NotificationPermissionState.GRANTED]
 * (including every device below Android 13, where no runtime grant exists) or
 * [NotificationPermissionState.DENIED] — a denial is the user's own decision,
 * Android will not re-show the dialog for it, and the settings screen already
 * carries the "open Settings" banner for that case.
 *
 * Dismissal is stored in SharedPreferences, which Android wipes along with the
 * app, so "not now" holds for this install and a later reinstall asks again.
 */
@Composable
fun PushReauthBanner(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val authVm = AuthViewModel.get()
    val notifyPush by authVm.notifyPushEnabled.collectAsStateWithLifecycle()

    var permState by remember { mutableStateOf(notificationPermissionState(context)) }
    var dismissed by remember { mutableStateOf(bannerDismissed(context)) }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        // Catches a grant made in system Settings while the app was
        // backgrounded, so the banner disappears on return.
        val observer = LifecycleEventObserver { _, event ->
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
        if (granted) {
            PushTokenManager.get().registerIfPermitted()
        } else {
            // They were asked and said no. Stop showing it; the settings
            // screen still explains how to turn notifications back on.
            setBannerDismissed(context)
            dismissed = true
        }
    }

    val visible = notifyPush &&
        permState == NotificationPermissionState.NOT_DETERMINED &&
        !dismissed
    if (!visible) return

    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(BrandOrange.copy(alpha = 0.10f))
            .border(1.dp, BrandOrange.copy(alpha = 0.30f), RoundedCornerShape(14.dp))
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(
            imageVector = Icons.Filled.Notifications,
            contentDescription = null,
            tint = BrandOrange,
            modifier = Modifier.size(18.dp).padding(top = 1.dp),
        )

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "Turn notifications back on",
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Spacer(Modifier.height(3.dp))
            Text(
                text = "Push is off on this device. Your alert types are still saved.",
                fontSize = 12.sp,
                color = TextSecondary,
            )
            Spacer(Modifier.height(10.dp))
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(BrandOrange.copy(alpha = 0.85f))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        }
                    }
                    .padding(horizontal = 14.dp, vertical = 7.dp),
            ) {
                Text(
                    text = "Turn back on",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White,
                )
            }
        }

        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) {
                    setBannerDismissed(context)
                    dismissed = true
                },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = "Dismiss",
                tint = TextSecondary,
                modifier = Modifier.size(14.dp),
            )
        }
    }
}
