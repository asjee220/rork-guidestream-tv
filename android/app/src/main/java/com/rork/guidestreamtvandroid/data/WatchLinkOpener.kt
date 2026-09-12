package com.rork.guidestreamtvandroid.data

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.rork.guidestreamtvandroid.data.repository.RakutenManager
import com.rork.guidestreamtvandroid.ui.components.openInAppBrowser

/**
 * Opens a Watch target: the streaming app when it is installed, otherwise the
 * title's page on the service's own site, inside GuideStream.
 *
 * The Android counterpart to `StreamingDeepLinker` on iOS, and it exists for
 * the same reason: an `ACTION_VIEW` on an https URL goes to the app only when
 * the app is installed AND has verified the link. Otherwise Android hands it
 * to the default browser, and the viewer is dropped out of GuideStream into
 * Chrome. Here the web case stays in a Custom Tab, wearing the app's own navy
 * and orange chrome, and carries affiliate tracking when the service has a
 * merchant id.
 */
fun openWatchLink(
    context: Context,
    target: String,
    serviceName: String?,
    webFallback: String?,
) {
    val uri = runCatching { Uri.parse(target) }.getOrNull()
    val scheme = uri?.scheme?.lowercase()
    val targetIsWeb = scheme == "http" || scheme == "https"

    val launched = when {
        target.startsWith("intent:") -> runCatching {
            context.startActivity(Intent.parseUri(target, Intent.URI_INTENT_SCHEME))
            true
        }.getOrDefault(false)

        targetIsWeb && uri != null -> startInClaimingApp(context, uri)

        uri != null -> runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, uri))
            true
        }.getOrDefault(false)

        else -> false
    }
    if (launched) return

    // Nothing on the device wanted it. Land on the service's own site rather
    // than on nothing, and keep it inside the app.
    val destination = webFallback?.takeIf { it.isNotBlank() }
        ?: target.takeIf { targetIsWeb }
        ?: return

    val rakuten = RakutenManager.get()
    val key = serviceName?.takeIf { it.isNotBlank() }?.let { rakuten.affiliateKey(it) }
    val tracked = key?.let { rakuten.trackingUrl(it, destination) }
    openInAppBrowser(context, tracked ?: destination)
}

/**
 * Starts the link only if a real app claims it - never a browser.
 *
 * On Android 11+ `FLAG_ACTIVITY_REQUIRE_NON_BROWSER` asks the system that
 * question directly and throws [ActivityNotFoundException] when the answer is
 * no, which needs no `<queries>` visibility at all. Below 11 there is no
 * package-visibility filtering, so the same question is answered by
 * subtracting the packages that claim *every* http link - the browsers - from
 * the packages that claim this one.
 */
private fun startInClaimingApp(context: Context, uri: Uri): Boolean {
    val view = Intent(Intent.ACTION_VIEW, uri)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        return runCatching {
            context.startActivity(
                Intent(view).addFlags(Intent.FLAG_ACTIVITY_REQUIRE_NON_BROWSER)
            )
            true
        }.getOrDefault(false)
    }

    val pm = context.packageManager
    val browsers = runCatching {
        pm.queryIntentActivities(Intent(Intent.ACTION_VIEW, Uri.parse("http://example.com")), 0)
            .map { it.activityInfo.packageName }
            .toSet()
    }.getOrDefault(emptySet())
    val claimants = runCatching {
        pm.queryIntentActivities(view, 0)
            .map { it.activityInfo.packageName }
            .toSet()
    }.getOrDefault(emptySet())

    if ((claimants - browsers).isEmpty()) return false
    return runCatching {
        context.startActivity(view)
        true
    }.getOrDefault(false)
}
