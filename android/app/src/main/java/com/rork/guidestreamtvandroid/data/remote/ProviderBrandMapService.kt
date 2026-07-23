package com.rork.guidestreamtvandroid.data.remote

import android.util.Log
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Read-only accessor for the public.provider_brand_map table (331 rows,
 * refreshed weekly by a server-side cron). Maps TMDB watch-provider ids
 * to the app's streaming-service catalogue ids so Platform resolution can
 * key off the stable TMDB id rather than a display name.
 *
 * Mirrors iOS ProviderBrandMapService.swift. Singleton with an in-memory
 * cache refreshed once per launch via [refresh]. The local catalogue
 * derivation in Platform.from() handles the first-render case before the
 * network fetch completes. Never throws — callers fall back gracefully.
 */
class ProviderBrandMapService private constructor() {

    @Serializable
    data class ProviderBrandRow(
        @SerialName("tmdb_provider_id") val tmdbProviderId: Int,
        @SerialName("display_name") val displayName: String,
        @SerialName("logo_path") val logoPath: String? = null,
        @SerialName("catalog_id") val catalogId: String? = null,
        @SerialName("aliases") val aliases: List<String> = emptyList(),
        @SerialName("link_source") val linkSource: String = "",
        @SerialName("badge_label") val badgeLabel: String? = null,
        @SerialName("badge_hex") val badgeHex: String? = null,
    )

    /** Cached brand-map rows — populated by [refresh]. Empty until the
     * first successful fetch; Platform.from() falls back to local catalogue
     * derivation while this is empty. */
    @Volatile
    var rows: List<ProviderBrandRow> = emptyList()
        private set

    /** Fetches all rows from provider_brand_map and updates the in-memory
     * cache. Returns silently on failure so callers can continue with the
     * local catalogue fallback. */
    suspend fun refresh() {
        try {
            val fetched: List<ProviderBrandRow> = SupabaseManager.client.postgrest["provider_brand_map"]
                .select()
                .decodeList<ProviderBrandRow>()
            rows = fetched
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            Log.e(TAG, "refresh failed: ${e.message}", e)
        }
    }

    companion object {
        private const val TAG = "ProviderBrandMap"

        @Volatile private var instance: ProviderBrandMapService? = null

        fun get(): ProviderBrandMapService = instance ?: synchronized(this) {
            instance ?: ProviderBrandMapService().also { instance = it }
        }
    }
}
