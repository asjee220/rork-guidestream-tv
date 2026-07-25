package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.rork.guidestreamtvandroid.data.remote.RemoteConfigService
import com.rork.guidestreamtvandroid.data.remote.RemoteConfigService.RemoteAdvertiser
import java.net.URLEncoder

/**
 * Rakuten Advertising affiliate entry — mirrors iOS RakutenAffiliate.
 * Opens trackable deep links that earn commission when users subscribe
 * to streaming services, with a direct sign-up fallback if the tracking
 * URL fails or the merchant id is still a placeholder.
 */
data class RakutenAffiliate(
    val service: String,
    val merchantId: String,
    val trackingUrl: String,
    val fallbackUrl: String,
    /** "cpa" = per signup, "cps" = per sale. */
    val commissionType: String,
)

/** Rakuten Publisher ID — matches the iOS RakutenManager. */
private const val PUBLISHER_ID = "lVjcZs0f2q0"

/**
 * Rakuten affiliate link manager — mirrors iOS RakutenManager.swift.
 *
 * The advertiser catalog is now remotely configurable via
 * `public.affiliate_advertisers` in Supabase. When remote rows are loaded,
 * they drive matching, signup URLs, fallback URLs, and merchant IDs. The
 * hardcoded eight-entry catalog below is kept purely as an offline fallback
 * so a first launch with no network behaves identically to today.
 */
class RakutenManager private constructor() {

    /**
     * Streaming service affiliate entries keyed by service id, matching the
     * iOS affiliate map (publisher id, click.linksynergy.com tracking URL
     * shapes, placeholder merchant ids, and direct sign-up fallbacks).
     * Kept as the offline fallback catalog — when `affiliate_advertisers` is
     * reachable, remote rows take precedence.
     */
    val affiliates: Map<String, RakutenAffiliate> = mapOf(
        "netflix" to RakutenAffiliate(
            service = "Netflix",
            merchantId = "[NETFLIX_MERCHANT_ID]",
            trackingUrl = "https://click.linksynergy.com/deeplink?id=$PUBLISHER_ID&mid=[NETFLIX_MERCHANT_ID]&murl=https%3A%2F%2Fwww.netflix.com%2Fsignup",
            fallbackUrl = "https://www.netflix.com/signup",
            commissionType = "cpa",
        ),
        "hulu" to RakutenAffiliate(
            service = "Hulu",
            merchantId = "[HULU_MERCHANT_ID]",
            trackingUrl = "https://click.linksynergy.com/deeplink?id=$PUBLISHER_ID&mid=[HULU_MERCHANT_ID]&murl=https%3A%2F%2Fwww.hulu.com%2Fstart",
            fallbackUrl = "https://www.hulu.com/start",
            commissionType = "cpa",
        ),
        "disney" to RakutenAffiliate(
            service = "Disney+",
            merchantId = "[DISNEY_MERCHANT_ID]",
            trackingUrl = "https://click.linksynergy.com/deeplink?id=$PUBLISHER_ID&mid=[DISNEY_MERCHANT_ID]&murl=https%3A%2F%2Fwww.disneyplus.com%2Fsign-up",
            fallbackUrl = "https://www.disneyplus.com/sign-up",
            commissionType = "cpa",
        ),
        "hbo" to RakutenAffiliate(
            service = "Max",
            merchantId = "[HBO_MERCHANT_ID]",
            trackingUrl = "https://click.linksynergy.com/deeplink?id=$PUBLISHER_ID&mid=[HBO_MERCHANT_ID]&murl=https%3A%2F%2Fwww.max.com%2Fplans-and-pricing",
            fallbackUrl = "https://www.max.com/plans-and-pricing",
            commissionType = "cpa",
        ),
        "appletv" to RakutenAffiliate(
            service = "Apple TV+",
            merchantId = "[APPLE_MERCHANT_ID]",
            trackingUrl = "https://click.linksynergy.com/deeplink?id=$PUBLISHER_ID&mid=[APPLE_MERCHANT_ID]&murl=https%3A%2F%2Ftv.apple.com",
            fallbackUrl = "https://tv.apple.com",
            commissionType = "cpa",
        ),
        "peacock" to RakutenAffiliate(
            service = "Peacock",
            merchantId = "[PEACOCK_MERCHANT_ID]",
            trackingUrl = "https://click.linksynergy.com/deeplink?id=$PUBLISHER_ID&mid=[PEACOCK_MERCHANT_ID]&murl=https%3A%2F%2Fwww.peacocktv.com%2Fplan",
            fallbackUrl = "https://www.peacocktv.com/plan",
            commissionType = "cpa",
        ),
        "paramount" to RakutenAffiliate(
            service = "Paramount+",
            merchantId = "[PARAMOUNT_MERCHANT_ID]",
            trackingUrl = "https://click.linksynergy.com/deeplink?id=$PUBLISHER_ID&mid=[PARAMOUNT_MERCHANT_ID]&murl=https%3A%2F%2Fwww.paramountplus.com%2Fsignup",
            fallbackUrl = "https://www.paramountplus.com/signup",
            commissionType = "cpa",
        ),
        "prime" to RakutenAffiliate(
            service = "Prime Video",
            merchantId = "[PRIME_MERCHANT_ID]",
            trackingUrl = "https://click.linksynergy.com/deeplink?id=$PUBLISHER_ID&mid=[PRIME_MERCHANT_ID]&murl=https%3A%2F%2Fwww.amazon.com%2Famazonprimevideo",
            fallbackUrl = "https://www.amazon.com/amazonprimevideo",
            commissionType = "cpa",
        ),
    )

    // MARK: - Effective catalog

    /**
     * Returns the effective advertiser catalog: remote rows from
     * `affiliate_advertisers` when non-empty, otherwise the hardcoded
     * affiliates mapped into `RemoteAdvertiser` shape.
     */
    private fun effectiveCatalog(): List<RemoteAdvertiser> {
        val remote = RemoteConfigService.affiliateCatalog()
        if (remote.isNotEmpty()) return remote
        return hardcodedCatalog()
    }

    /**
     * Maps the hardcoded `affiliates` map into `RemoteAdvertiser` shape so
     * the fallback path uses the same resolution code as the remote path.
     * Aliases are derived from the existing contains-logic.
     */
    private fun hardcodedCatalog(): List<RemoteAdvertiser> {
        val aliasMap = mapOf(
            "netflix" to listOf("netflix"),
            "hbo" to listOf("max", "hbo"),
            "hulu" to listOf("hulu"),
            "disney" to listOf("disney"),
            "apple" to listOf("apple"),
            "prime" to listOf("prime", "amazon"),
            "paramount" to listOf("paramount"),
            "peacock" to listOf("peacock"),
        )
        val order = listOf("netflix", "hbo", "hulu", "disney", "apple", "prime", "paramount", "peacock")
        return order.mapIndexedNotNull { index, key ->
            val aff = affiliates[key] ?: return@mapIndexedNotNull null
            val signup = directSignupURL(key) ?: ""
            RemoteAdvertiser(
                key = key,
                displayName = aff.service,
                aliases = aliasMap[key] ?: listOf(key),
                merchantId = null,
                signupUrl = signup,
                fallbackUrl = aff.fallbackUrl,
                commissionType = aff.commissionType,
                enabled = true,
                sortOrder = index,
            )
        }
    }

    // MARK: - Matching

    /** Resolves a service display name or catalog id to an affiliate key. */
    fun affiliateKey(serviceName: String): String? {
        val lowered = serviceName.lowercase()
        return effectiveCatalog().firstOrNull { entry ->
            entry.aliases.any { lowered.contains(it) }
        }?.key
    }

    /** Returns true when an affiliate entry exists for the given service. */
    fun hasAffiliate(serviceName: String): Boolean =
        affiliateKey(serviceName) != null

    fun affiliate(serviceId: String): RakutenAffiliate? {
        val normalized = serviceId.lowercase()
        val entry = effectiveCatalog().firstOrNull { it.key == normalized } ?: return null
        return RakutenAffiliate(
            service = entry.displayName,
            merchantId = entry.merchantId ?: "",
            trackingUrl = affiliateURL(normalized) ?: "",
            fallbackUrl = entry.fallbackUrl ?: "",
            commissionType = entry.commissionType,
        )
    }

    /**
     * Builds the Rakuten tracking URL at call time so it always reflects the
     * latest remote config. Resolves the publisher id from RemoteConfigService
     * falling back to the hardcoded PUBLISHER_ID constant, reads the matched
     * entry's merchantId, and when non-blank builds the URL as
     * https://click.linksynergy.com/deeplink?id=PUBLISHER&mid=MERCHANT&murl=ENCODED
     * where ENCODED is the percent-encoded entry's signupUrl. When no merchant
     * id is available, returns null so the caller falls through to the
     * direct-signup branch.
     */
    fun affiliateURL(serviceId: String): String? {
        val normalized = serviceId.lowercase()
        val entry = effectiveCatalog().firstOrNull { it.key == normalized } ?: return null
        val resolvedPublisher = RemoteConfigService.rakutenPublisherId() ?: PUBLISHER_ID
        val merchantId = entry.merchantId
        if (merchantId.isNullOrBlank()) {
            return null
        }
        val encoded = URLEncoder.encode(entry.signupUrl, "UTF-8")
        return "https://click.linksynergy.com/deeplink?id=$resolvedPublisher&mid=$merchantId&murl=$encoded"
    }

    private fun fallbackURL(serviceId: String): String? {
        val normalized = serviceId.lowercase()
        val entry = effectiveCatalog().firstOrNull { it.key == normalized } ?: return null
        return entry.fallbackUrl?.takeIf { it.isNotBlank() }
    }

    /**
     * Opens the Rakuten tracking URL for the given service id, falling back
     * to the direct sign-up URL if the merchant id is missing or the tracking
     * URL fails to open. Always logs an affiliate_link_tapped event.
     */
    fun openAffiliateLink(
        serviceId: String,
        context: Context,
        metadata: Map<String, Any> = emptyMap(),
    ) {
        val normalized = serviceId.lowercase()
        val trackingUrl = affiliateURL(normalized)
        val isDirectFallback = trackingUrl == null

        // Resolve the direct-signup target from the entry's signupUrl, falling
        // back to directSignupURL when the entry has no signupUrl or the key
        // is unknown (espn/disney_bundle/default cases).
        val entry = effectiveCatalog().firstOrNull { it.key == normalized }
        val directSignup = entry?.signupUrl?.takeIf { it.isNotBlank() } ?: directSignupURL(normalized)
        val targetUrl = trackingUrl ?: fallbackURL(normalized) ?: directSignup

        if (targetUrl != null) {
            try {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(targetUrl)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            } catch (_: Exception) {
                val fallback = fallbackURL(normalized) ?: directSignupURL(normalized)
                if (fallback != null) {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(fallback)).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                    } catch (_: Exception) {
                        // Nothing more we can do — never crash on a tap.
                    }
                }
            }
        }

        val meta = buildMap<String, Any> {
            put("type", if (isDirectFallback) "direct_fallback" else "subscribe_cta")
            putAll(metadata)
        }
        WatchIntentLogger.get().log(
            WatchIntentLogger.IntentEventType.AFFILIATE_LINK_TAPPED,
            platformId = normalized,
            metadata = meta,
        )
    }

    private fun directSignupURL(serviceId: String): String? = when (serviceId) {
        "netflix" -> "https://www.netflix.com/signup"
        "hbo" -> "https://www.max.com/plans-and-pricing"
        "hulu" -> "https://www.hulu.com/start"
        "disney" -> "https://www.disneyplus.com/sign-up"
        "appletv", "apple" -> "https://tv.apple.com"
        "prime" -> "https://www.amazon.com/amazonprimevideo"
        "paramount" -> "https://www.paramountplus.com/signup"
        "peacock" -> "https://www.peacocktv.com/plan"
        else -> "https://www.google.com/search?q=$serviceId+streaming+free+trial"
    }

    companion object {
        @Volatile private var instance: RakutenManager? = null
        fun get(): RakutenManager = instance ?: synchronized(this) {
            instance ?: RakutenManager().also { instance = it }
        }
    }
}
