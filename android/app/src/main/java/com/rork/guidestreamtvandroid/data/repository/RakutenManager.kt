package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import android.content.Intent
import android.net.Uri

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
 * Register for each program at rakutenadvertising.com/publishers/programs
 * and swap in real merchant ids to start earning.
 */
class RakutenManager private constructor() {

    /**
     * Streaming service affiliate entries keyed by service id, matching the
     * iOS affiliate map (publisher id, click.linksynergy.com tracking URL
     * shapes, placeholder merchant ids, and direct sign-up fallbacks).
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

    /** Resolves a service display name or catalog id to an affiliate key. */
    fun affiliateKey(serviceName: String): String? {
        val key = serviceName.lowercase()
        return when {
            key.contains("netflix") -> "netflix"
            key.contains("max") || key.contains("hbo") -> "hbo"
            key.contains("hulu") -> "hulu"
            key.contains("disney") -> "disney"
            key.contains("apple") -> "appletv"
            key.contains("prime") || key.contains("amazon") -> "prime"
            key.contains("paramount") -> "paramount"
            key.contains("peacock") -> "peacock"
            else -> null
        }
    }

    /** Returns true when an affiliate entry exists for the given service. */
    fun hasAffiliate(serviceName: String): Boolean =
        affiliateKey(serviceName) != null

    fun affiliate(serviceId: String): RakutenAffiliate? =
        affiliates[serviceId.lowercase()]

    fun affiliateURL(serviceId: String): String? =
        affiliate(serviceId)?.trackingUrl

    private fun fallbackURL(serviceId: String): String? =
        affiliate(serviceId)?.fallbackUrl

    /**
     * Opens the Rakuten tracking URL for the given service id, falling back
     * to the direct sign-up URL if the merchant id is still a placeholder or
     * the tracking URL fails to open. Always logs an affiliate_link_tapped
     * event for attribution analytics.
     */
    fun openAffiliateLink(
        serviceId: String,
        context: Context,
        metadata: Map<String, Any> = emptyMap(),
    ) {
        val normalized = serviceId.lowercase()
        val affiliate = affiliate(normalized)

        // If the merchant id is still a placeholder, skip Rakuten entirely and
        // open the direct sign-up URL so the link always works.
        val isPlaceholder = affiliate?.merchantId?.startsWith("[") ?: true
        val targetUrl = if (isPlaceholder) {
            fallbackURL(normalized) ?: directSignupURL(normalized)
        } else {
            affiliateURL(normalized)
        }

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
            put("type", if (isPlaceholder) "direct_fallback" else "subscribe_cta")
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
