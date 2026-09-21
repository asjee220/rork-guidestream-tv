package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.RecommendedTitle
import com.rork.guidestreamtvandroid.data.remote.StreamingReleasesService
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Last-known Home rails, persisted so the next launch paints real content
 * immediately instead of a shimmer while the cold load completes. Only the
 * TMDB-backed rails, the streaming_releases rows and the resolved provider
 * names are stored — live sports, creator uploads and anything time-sensitive
 * are refetched. Mirrors iOS HomeSnapshotStore.swift.
 */
@Serializable
data class HomeSnapshot(
    val version: Int = HomeSnapshot.CURRENT_VERSION,
    val savedAtMs: Long,
    val trending: List<TMDBResult>,
    val onAir: List<TMDBResult>,
    val topRated: List<TMDBResult>,
    val genreShows: List<TMDBResult>,
    val bingeReady: List<TMDBResult>,
    val releaseRows: List<StreamingReleasesService.StreamingReleaseRow>,
    /** Recommended for You — the first rail under the hero; without it the
     * snapshot paints Today's Pick first and the page reflows when it lands. */
    val recommendedTitles: List<RecommendedTitle> = emptyList(),
    /** tmdbId → provider display name, rebuilt into Platform on load. */
    val providerNames: Map<Int, String>,
) {
    companion object { const val CURRENT_VERSION = 2 }
}

object HomeSnapshotStore {
    /** Snapshots older than this are ignored rather than shown stale. */
    private const val MAX_AGE_MS = 24L * 60 * 60 * 1000

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    @Volatile private var file: File? = null

    fun init(context: Context) {
        file = File(context.applicationContext.cacheDir, "home_snapshot_v${HomeSnapshot.CURRENT_VERSION}.json")
    }

    fun load(): HomeSnapshot? {
        val f = file ?: return null
        return try {
            if (!f.exists()) return null
            val snap = json.decodeFromString(HomeSnapshot.serializer(), f.readText())
            if (snap.version != HomeSnapshot.CURRENT_VERSION) return null
            if (System.currentTimeMillis() - snap.savedAtMs > MAX_AGE_MS) return null
            if (snap.trending.isEmpty()) return null
            snap
        } catch (_: Exception) {
            null
        }
    }

    fun save(snapshot: HomeSnapshot) {
        val f = file ?: return
        try {
            val tmp = File(f.parentFile, f.name + ".tmp")
            tmp.writeText(json.encodeToString(HomeSnapshot.serializer(), snapshot))
            if (!tmp.renameTo(f)) { f.writeText(tmp.readText()); tmp.delete() }
        } catch (_: Exception) {}
    }

    fun clear() {
        try { file?.delete() } catch (_: Exception) {}
    }
}
