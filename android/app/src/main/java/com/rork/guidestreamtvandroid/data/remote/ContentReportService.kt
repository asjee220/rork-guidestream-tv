package com.rork.guidestreamtvandroid.data.remote

import android.content.Context
import com.rork.guidestreamtvandroid.BuildConfig
import com.rork.guidestreamtvandroid.SupabaseConfig
import com.rork.guidestreamtvandroid.data.DeviceLocale
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import io.ktor.client.HttpClient
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/*
 * In-app "Report a problem" (30 Sep 2026) — parity with iOS
 * ContentReportService.swift. Entry points:
 *  A  "Wrong service or link? Report it" under Where to Watch (episode sheet,
 *     show detail).
 *  C  DeepLinkReturnCheck: "Did <service> open <title>?" on return from a
 *     streaming app; answers go to watch_intent_events as deeplink_confirmed /
 *     deeplink_failed, "No" opens the report sheet.
 *  D  "Wrong channel or time?" in SportsWatchSheet.
 * Reports post to the content_report edge function (verify_jwt = false).
 * The sheets are drawn by ReportHost at the app root, so any screen can open
 * one through ReportCenter.
 */

enum class ContentReportKind(val value: String) { TITLE("title"), SPORTS("sports") }

enum class ReportReason(val value: String, val label: String) {
    WRONG_SERVICE("wrong_service", "Wrong streaming service"),
    LINK_BROKEN("link_broken", "Button didn’t open it"),
    UNAVAILABLE("unavailable", "No longer available here"),
    WRONG_PRICE("wrong_price", "Wrong price or plan (free / paid)"),
    WRONG_DETAILS("wrong_details", "Wrong details or artwork"),
    WRONG_CHANNEL("wrong_channel", "Wrong channel or service"),
    WRONG_TIME("wrong_time", "Wrong start time"),
    OTHER("other", "Something else");

    companion object {
        fun options(kind: ContentReportKind): List<ReportReason> = when (kind) {
            ContentReportKind.TITLE -> listOf(WRONG_SERVICE, LINK_BROKEN, UNAVAILABLE, WRONG_PRICE, WRONG_DETAILS, OTHER)
            ContentReportKind.SPORTS -> listOf(WRONG_CHANNEL, WRONG_TIME, LINK_BROKEN, OTHER)
        }
    }
}

data class ReportContext(
    val kind: ContentReportKind = ContentReportKind.TITLE,
    /** detail_link | deeplink_return | sports_link */
    val entryPoint: String,
    val titleName: String,
    val providerName: String? = null,
    val titleId: String? = null,
    val tmdbId: Int? = null,
    val isTV: Boolean? = null,
    val gameId: String? = null,
    val preselected: ReportReason? = null,
)

object ContentReportService {
    private val client: HttpClient by lazy { HttpClient() }

    /** True only on a 2xx, so the sheet can keep the input for a retry. */
    suspend fun submit(ctx: ReportContext, reason: ReportReason, note: String): Boolean {
        return try {
            val deviceId = runCatching { DeviceIdentity.get().deviceId }.getOrNull()
            val userId = runCatching { AuthViewModel.get().currentUserId }.getOrNull()
            val body = buildJsonObject {
                put("kind", JsonPrimitive(ctx.kind.value))
                put("entry_point", JsonPrimitive(ctx.entryPoint))
                put("reason", JsonPrimitive(reason.value))
                put("title_name", JsonPrimitive(ctx.titleName))
                put("region", JsonPrimitive(DeviceLocale.region))
                put("platform", JsonPrimitive("android"))
                put("app_version", JsonPrimitive(BuildConfig.VERSION_NAME))
                ctx.providerName?.takeIf { it.isNotBlank() }?.let { put("provider_name", JsonPrimitive(it)) }
                ctx.titleId?.let { put("title_id", JsonPrimitive(it)) }
                ctx.tmdbId?.let { put("tmdb_id", JsonPrimitive(it)) }
                ctx.isTV?.let { put("media_type", JsonPrimitive(if (it) "tv" else "movie")) }
                ctx.gameId?.let { put("game_id", JsonPrimitive(it)) }
                if (deviceId != null) put("device_id", JsonPrimitive(deviceId))
                if (userId != null) put("user_id", JsonPrimitive(userId))
                note.trim().takeIf { it.isNotEmpty() }?.let { put("note", JsonPrimitive(it)) }
            }
            val url = "${SupabaseConfig.URL.trim()}/functions/v1/content_report"
            val response: HttpResponse = client.post(url) {
                contentType(ContentType.Application.Json)
                header("apikey", SupabaseConfig.ANON_KEY)
                header(HttpHeaders.Authorization, "Bearer ${SupabaseConfig.ANON_KEY}")
                setBody(body.toString())
            }
            response.status.value in 200..299
        } catch (_: Exception) {
            false
        }
    }
}

/** What ReportHost should be showing. */
object ReportCenter {
    private val _report = MutableStateFlow<ReportContext?>(null)
    val report: StateFlow<ReportContext?> = _report

    private val _returnCheck = MutableStateFlow<DeepLinkReturnCheck.Pending?>(null)
    val returnCheck: StateFlow<DeepLinkReturnCheck.Pending?> = _returnCheck

    fun open(ctx: ReportContext) { _report.value = ctx }
    fun closeReport() { _report.value = null }
    internal fun showReturnCheck(p: DeepLinkReturnCheck.Pending) { _returnCheck.value = p }
    fun closeReturnCheck() { _returnCheck.value = null }
}

/**
 * C — armed on every outbound watch tap; shown only when the app really went
 * to the background, the user came back 4 s – 20 min later, and it has not
 * been shown in the last 12 h.
 */
object DeepLinkReturnCheck {
    data class Pending(
        val title: String,
        val platform: String,
        val tmdbId: Int?,
        val titleId: String?,
        val gameId: String?,
        val armedAt: Long,
    ) {
        val reportContext: ReportContext
            get() = ReportContext(
                kind = if (gameId == null) ContentReportKind.TITLE else ContentReportKind.SPORTS,
                entryPoint = "deeplink_return",
                titleName = title,
                providerName = platform,
                titleId = titleId,
                tmdbId = tmdbId,
                gameId = gameId,
                preselected = ReportReason.LINK_BROKEN,
            )
    }

    private const val PREFS = "gs_prefs"
    private const val KEY_LAST_SHOWN = "gs.deeplinkReturnCheck.lastShown"
    private const val MIN_INTERVAL_MS = 12 * 60 * 60 * 1000L
    private const val MIN_AWAY_MS = 4_000L
    private const val MAX_AWAY_MS = 20 * 60 * 1000L

    @Volatile private var pending: Pending? = null
    @Volatile private var leftApp = false

    fun arm(title: String, platform: String?, tmdbId: Int?, titleId: String?, gameId: String? = null) {
        val p = platform?.trim().orEmpty()
        if (p.isEmpty() || title.isBlank()) return
        pending = Pending(title, p, tmdbId, titleId, gameId, System.currentTimeMillis())
        leftApp = false
    }

    fun noteBackgrounded() {
        if (pending != null) leftApp = true
    }

    /** True when the card is being shown, so the review prompt waits. */
    fun appDidBecomeActive(context: Context): Boolean {
        val p = pending ?: return false
        val elapsed = System.currentTimeMillis() - p.armedAt
        if (!leftApp) {
            if (elapsed > MAX_AWAY_MS) pending = null
            return false
        }
        pending = null
        leftApp = false
        if (elapsed < MIN_AWAY_MS || elapsed > MAX_AWAY_MS) return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        if (now - prefs.getLong(KEY_LAST_SHOWN, 0L) < MIN_INTERVAL_MS) return false
        prefs.edit().putLong(KEY_LAST_SHOWN, now).apply()
        ReportCenter.showReturnCheck(p)
        return true
    }

    fun record(p: Pending, opened: Boolean) {
        WatchIntentLogger.get().log(
            if (opened) WatchIntentLogger.IntentEventType.DEEPLINK_CONFIRMED
            else WatchIntentLogger.IntentEventType.DEEPLINK_FAILED,
            titleId = p.titleId ?: p.tmdbId?.toString() ?: WatchIntentLogger.get().titleSlug(p.title),
            platformId = p.platform,
            metadata = mapOf(
                "platform_name" to p.platform,
                "tmdb_id" to (p.tmdbId?.toString() ?: ""),
                "game_id" to (p.gameId ?: ""),
                "seconds_away" to ((System.currentTimeMillis() - p.armedAt) / 1000),
            ),
        )
    }
}
