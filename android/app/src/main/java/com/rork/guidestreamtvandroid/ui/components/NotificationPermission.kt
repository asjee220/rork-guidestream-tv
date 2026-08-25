package com.rork.guidestreamtvandroid.ui.components

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat

/**
 * Runtime state of the POST_NOTIFICATIONS permission.
 *
 * Android cannot distinguish "never asked" from "denied" through
 * [ContextCompat.checkSelfPermission] alone, so the `gs.notifPermissionAsked`
 * flag written when the system dialog is shown fills the gap. Uninstalling the
 * app clears both the permission and that flag, which is why a reinstall lands
 * back on [NOT_DETERMINED] rather than [DENIED].
 *
 * Mirrors the iOS `UNAuthorizationStatus` handling in NotificationsSettingsView.
 */
enum class NotificationPermissionState {
    NOT_DETERMINED,
    GRANTED,
    DENIED,
}

private const val PREFS_NAME = "gs_prefs"
private const val ASKED_KEY = "gs.notifPermissionAsked"

/**
 * Reads the live permission state. Always [GRANTED] below Android 13, where
 * POST_NOTIFICATIONS does not exist and notifications need no runtime grant.
 */
fun notificationPermissionState(context: Context): NotificationPermissionState {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
        return NotificationPermissionState.GRANTED
    }
    val granted = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.POST_NOTIFICATIONS,
    ) == PackageManager.PERMISSION_GRANTED
    val asked = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getBoolean(ASKED_KEY, false)
    return when {
        granted -> NotificationPermissionState.GRANTED
        asked -> NotificationPermissionState.DENIED
        else -> NotificationPermissionState.NOT_DETERMINED
    }
}

/** Records that the system permission dialog has been shown at least once. */
fun markNotificationPermissionAsked(context: Context) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .putBoolean(ASKED_KEY, true)
        .apply()
}

/**
 * Opens this app's notification settings so a denied grant can be restored —
 * Android never re-shows the runtime dialog after a denial.
 */
fun openAppNotificationSettings(context: Context) {
    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
    } else {
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.fromParts("package", context.packageName, null))
    }
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(intent) }
}
