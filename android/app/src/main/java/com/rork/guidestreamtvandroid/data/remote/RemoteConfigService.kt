package com.rork.guidestreamtvandroid.data.remote

import android.content.Context
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager.client
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

/**
 * Lightweight remote-configuration layer — mirrors iOS RemoteConfigService.swift.
 *
 * Reads AdMob ad unit IDs and Rakuten merchant IDs from `public.app_config`
 * via the existing Supabase client so they can be updated without shipping a
 * new build. Hydrates synchronously from a SharedPreferences cache on init
 * so values are available immediately at cold launch before the network
 * returns. `load()` never throws and silently no-ops on any failure, leaving
 * cached or hardcoded values intact.
 *
 * No secrets, tokens, or API keys are stored in or read from `app_config`.
 */
object RemoteConfigService {

    private const val CACHE_KEY = "gs_remote_config_cache"
    private const val PREFS_NAME = "gs_prefs"

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    @Volatile private var adsConfig: RemoteAdConfig? = null
    @Volatile private var rakutenConfig: RemoteRakutenConfig? = null
    @Volatile private var appContext: Context? = null

    @Serializable
    private data class RemoteAdConfig(
        val banner: String? = null,
        val interstitial: String? = null,
        val native: String? = null,
    )

    @Serializable
    private data class RemoteRakutenConfig(
        @SerialName("publisher_id") val publisherId: String? = null,
        val merchants: RemoteRakutenMerchants? = null,
    )

    @Serializable
    private data class RemoteRakutenMerchants(
        val netflix: String? = null,
        val hulu: String? = null,
        val disney: String? = null,
        val hbo: String? = null,
        val apple: String? = null,
        val peacock: String? = null,
        val paramount: String? = null,
        val prime: String? = null,
    )

    @Serializable
    private data class AppConfigRow(
        val key: String,
        val value: JsonElement,
    )

    /**
     * Synchronously hydrate from the SharedPreferences cache so values are
     * available before the network returns. Call from Application.onCreate()
     * before any ad or affiliate request fires. Also stashes the application
     * context so `load()` can write back to the cache.
     */
    fun init(context: Context) {
        appContext = context.applicationContext
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString(CACHE_KEY, null) ?: return
            val rows = json.decodeFromString<List<AppConfigRow>>(raw)
            ingest(rows, persist = false)
        } catch (_: Throwable) {
            // Corrupt cache — ignore; the network load will repopulate.
        }
    }

    /**
     * Reads all rows from `app_config`, decodes the three known keys, stores
     * them in memory, and persists the raw JSON to SharedPreferences. Never
     * throws — any failure leaves cached or hardcoded values intact.
     */
    suspend fun load() {
        try {
            val rows = client.postgrest
                .from("app_config")
                .select()
                .decodeList<AppConfigRow>()
            ingest(rows, persist = true)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            // Silent no-op: cached or hardcoded values stay in place.
        }
    }

    private fun ingest(rows: List<AppConfigRow>, persist: Boolean) {
        var newAds: RemoteAdConfig? = null
        var newRakuten: RemoteRakutenConfig? = null
        for (row in rows) {
            try {
                val data = json.encodeToString(JsonElement.serializer(), row.value)
                when (row.key) {
                    "ads_android" -> {
                        newAds = json.decodeFromString(RemoteAdConfig.serializer(), data)
                    }
                    "ads_ios" -> {
                        // Only used as a fallback when ads_android is missing.
                        if (newAds == null) {
                            newAds = json.decodeFromString(RemoteAdConfig.serializer(), data)
                        }
                    }
                    "affiliate_rakuten" -> {
                        newRakuten = json.decodeFromString(
                            RemoteRakutenConfig.serializer(),
                            data,
                        )
                    }
                }
            } catch (_: Throwable) {
                // Malformed row — skip; never crash.
            }
        }
        if (newAds != null) adsConfig = newAds
        if (newRakuten != null) rakutenConfig = newRakuten

        if (persist) {
            try {
                val encoded = json.encodeToString(
                    ListSerializer(AppConfigRow.serializer()),
                    rows,
                )
                appContext?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    ?.edit()?.putString(CACHE_KEY, encoded)?.apply()
            } catch (_: Throwable) {
                // Persistence failure is non-fatal.
            }
        }
    }

    /**
     * Returns the ad unit id for the given slot ("banner", "interstitial",
     * "native"), or null when the key is missing, null, or an empty string.
     */
    fun adUnit(slot: String): String? {
        val ads = adsConfig ?: return null
        val raw = when (slot) {
            "banner" -> ads.banner
            "interstitial" -> ads.interstitial
            "native" -> ads.native
            else -> null
        }
        return raw?.takeIf { it.isNotBlank() }
    }

    /** Returns the Rakuten publisher id, or null when missing/empty. */
    fun rakutenPublisherId(): String? =
        rakutenConfig?.publisherId?.takeIf { it.isNotBlank() }

    /**
     * Returns the Rakuten merchant id for the given service key (e.g.
     * "netflix", "hulu"), or null when missing/empty.
     */
    fun rakutenMerchantId(key: String): String? {
        val merchants = rakutenConfig?.merchants ?: return null
        val raw = when (key) {
            "netflix" -> merchants.netflix
            "hulu" -> merchants.hulu
            "disney" -> merchants.disney
            "hbo" -> merchants.hbo
            "apple" -> merchants.apple
            "peacock" -> merchants.peacock
            "paramount" -> merchants.paramount
            "prime" -> merchants.prime
            else -> null
        }
        return raw?.takeIf { it.isNotBlank() }
    }
}
