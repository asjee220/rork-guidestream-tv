package com.rork.guidestreamtvandroid.ui.ads

import android.content.Context
import android.content.pm.PackageManager
import com.rork.guidestreamtvandroid.AppConfig
import com.rork.guidestreamtvandroid.data.remote.RemoteConfigService

/**
 * Resolves which AdMob ad unit id to actually request for a given slot.
 *
 * AdMob refuses to serve when an ad unit's publisher id does not match the
 * publisher declared in the manifest's `com.google.android.gms.ads.APPLICATION_ID`
 * meta-data. Remote config can legitimately hand us a unit belonging to a
 * different publisher — most notably the iOS units, which live under a separate
 * AdMob app — and requesting one of those makes every request fail with no
 * fill, which looks like "ads are broken" rather than a configuration mistake.
 *
 * This resolver validates the remote unit against the manifest app id and falls
 * back to the bundled unit whenever they disagree, so a misconfigured
 * `app_config` row degrades to working ads instead of a blank app.
 */
object AdUnitResolver {

    /** Cached manifest app id so PackageManager is only queried once. */
    @Volatile private var cachedAppId: String? = null

    /** Why the most recent remote unit was rejected, surfaced in diagnostics. */
    @Volatile var lastRejectionReason: String? = null
        private set

    /**
     * The AdMob application id declared in the merged manifest, or null when
     * the meta-data entry is missing or unreadable.
     */
    fun appId(context: Context): String? {
        cachedAppId?.let { return it }
        val value = try {
            val info = context.packageManager.getApplicationInfo(
                context.packageName,
                PackageManager.GET_META_DATA,
            )
            info.metaData?.get("com.google.android.gms.ads.APPLICATION_ID")?.toString()
        } catch (_: Throwable) {
            null
        }
        cachedAppId = value
        return value
    }

    /**
     * Publisher portion of an AdMob identifier. App ids look like
     * `ca-app-pub-XXXX~YYYY` and unit ids like `ca-app-pub-XXXX/YYYY`, so the
     * publisher is everything before the separator.
     */
    private fun publisherOf(identifier: String?): String? {
        if (identifier.isNullOrBlank()) return null
        val separator = identifier.indexOfFirst { it == '~' || it == '/' }
        if (separator <= 0) return null
        return identifier.substring(0, separator)
    }

    /** True when [adUnitId] belongs to the same publisher as the manifest app id. */
    fun matchesManifestPublisher(context: Context, adUnitId: String?): Boolean {
        val appPublisher = publisherOf(appId(context)) ?: return false
        val unitPublisher = publisherOf(adUnitId) ?: return false
        return appPublisher == unitPublisher
    }

    /**
     * Returns the ad unit id to request for [slot] ("native", "interstitial",
     * "banner"). Prefers the remote-config value, but only when it belongs to
     * the same publisher as the manifest app id; otherwise returns [fallback].
     */
    fun resolve(context: Context, slot: String, fallback: String): String {
        val remote = RemoteConfigService.adUnit(slot)
        if (remote.isNullOrBlank()) return fallback
        if (matchesManifestPublisher(context, remote)) {
            lastRejectionReason = null
            return remote
        }
        lastRejectionReason =
            "Remote \"$slot\" unit $remote does not match manifest app id " +
                "${appId(context) ?: "(missing)"} — using bundled unit instead."
        return fallback
    }

    /** Convenience accessor for the native slot. */
    fun native(context: Context): String =
        resolve(context, "native", AppConfig.ADMOB_NATIVE_AD_UNIT_ID)

    /** Convenience accessor for the interstitial slot. */
    fun interstitial(context: Context): String =
        resolve(context, "interstitial", AppConfig.ADMOB_INTERSTITIAL_AD_UNIT_ID)
}
