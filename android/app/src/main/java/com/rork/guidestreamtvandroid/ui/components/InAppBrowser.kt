package com.rork.guidestreamtvandroid.ui.components

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabColorSchemeParams
import androidx.browser.customtabs.CustomTabsIntent

/**
 * Opens a URL inside the app using a Chrome Custom Tab (GUI-87).
 *
 * A Custom Tab renders the page over the app in GuideStream's own chrome -
 * navy toolbar, orange controls - instead of task-switching to the browser,
 * so Privacy, Terms and the YouTube terms read as part of the app. It is the
 * Android counterpart to SFSafariViewController on iOS.
 *
 * Falls back to a plain ACTION_VIEW when no Custom Tabs provider is installed
 * (some AOSP builds and most Amazon devices), so the link always resolves.
 */
fun openInAppBrowser(context: Context, url: String) {
    val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return
    val colors = CustomTabColorSchemeParams.Builder()
        .setToolbarColor(0xFF04090F.toInt())
        .setSecondaryToolbarColor(0xFF04090F.toInt())
        .setNavigationBarColor(0xFF04090F.toInt())
        .build()
    val intent = CustomTabsIntent.Builder()
        .setDefaultColorSchemeParams(colors)
        .setColorScheme(CustomTabsIntent.COLOR_SCHEME_DARK)
        .setShowTitle(true)
        .setUrlBarHidingEnabled(true)
        .setShareState(CustomTabsIntent.SHARE_STATE_OFF)
        .build()
    val opened = runCatching { intent.launchUrl(context, uri) }.isSuccess
    if (!opened) {
        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
    }
}
