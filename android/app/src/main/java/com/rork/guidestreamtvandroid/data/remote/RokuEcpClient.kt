package com.rork.guidestreamtvandroid.data.remote

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.net.URLEncoder

/**
 * Sends launch commands to a Roku device using the External Control Protocol.
 * Mirrors iOS `RokuECPClient.swift` one-for-one.
 *
 * ECP is plain HTTP on port 8060. Raw `java.net.Socket` is used because
 * Android's cleartext-traffic policy would block OkHttp or HttpURLConnection
 * calls to LAN IP literals.
 */
object RokuEcpClient {

    /** Maps a streaming platform label to the Roku channel ID. */
    object RokuChannel {
        fun id(platform: String): String? {
            val key = platform.lowercase()
                .replace("_", " ")
                .replace("-", " ")
                .filter { it.isLetterOrDigit() || it.isWhitespace() }

            if (key.contains("netflix")) return "12"
            if (key.contains("hbo") || key.contains(" max") || key.endsWith("max")) return "61322"
            if (key.contains("hulu")) return "2285"
            if (key.contains("disney")) return "291097"
            if (key.contains("prime") || key.contains("amazon")) return "13"
            if (key.contains("apple tv") || key.contains("appletv") || key.contains("apple ")) return "551012"
            if (key.contains("paramount")) return "31440"
            if (key.contains("peacock")) return "593099"
            if (key.contains("youtube tv") || key.contains("youtubetv")) return "195316"
            if (key.contains("youtube")) return "837"
            if (key.contains("showtime")) return "60308"
            if (key.contains("starz")) return "151908"
            if (key.contains("crunchyroll")) return "55307"
            if (key.contains("tubi")) return "41468"
            if (key.contains("pluto")) return "74519"
            if (key.contains("plex")) return "13535"
            return null
        }
    }

    /** Outcome of probing `/query/device-info` before attempting a launch. */
    enum class EcpStatus { ENABLED, LIMITED, UNREACHABLE }

    /** Outcome of a Roku ECP launch attempt. */
    sealed interface RokuLaunchResult {
        data object Ok : RokuLaunchResult
        data object LimitedMode : RokuLaunchResult
        data class Rejected(val status: Int) : RokuLaunchResult
        data object Unreachable : RokuLaunchResult
    }

    /**
     * Checks whether ECP is enabled on the Roku device. A device that answers
     * with any HTTP status is treated as `.ENABLED` — the launch path will
     * classify the real failure. Only a timeout or socket failure returns
     * `.UNREACHABLE`.
     */
    suspend fun checkEcpEnabled(host: String, port: Int): EcpStatus {
        val response = rawHttpRequest(host, port, "GET", "/query/device-info", 3000L)
        if (response == null) return EcpStatus.UNREACHABLE
        val code = parseStatusCode(response)
        return when {
            code == null -> EcpStatus.UNREACHABLE
            code in 200..299 -> EcpStatus.ENABLED
            code == 401 || code == 403 -> EcpStatus.LIMITED
            else -> EcpStatus.ENABLED
        }
    }

    /**
     * Launches a Roku channel using a Watchmode `roku_url` path.
     * Sends `/keypress/Home` first, then tries the launch path, falling back
     * to a bare `/launch/{channelId}` if the parameterised launch is rejected.
     */
    suspend fun launch(host: String, port: Int, rokuUrlPath: String): RokuLaunchResult {
        var normalized = rokuUrlPath.trim()
        if (normalized.contains("://")) {
            val launchIndex = normalized.indexOf("launch/")
            if (launchIndex >= 0) {
                normalized = normalized.substring(launchIndex)
            }
        }
        if (normalized.startsWith("/")) {
            normalized = normalized.drop(1)
        }
        if (!normalized.contains("launch/")) {
            return RokuLaunchResult.Unreachable
        }

        rawHttpPost(host, port, "/keypress/Home", 1200L)
        delay(1200)

        val outcome = rawHttpPost(host, port, "/$normalized", 4000L)
        if (outcome != null) {
            if (outcome in 200..299) return RokuLaunchResult.Ok
            if (outcome == 401 || outcome == 403) return RokuLaunchResult.LimitedMode

            val channelPart = normalized.replace("launch/", "")
            val channelId = channelPart.split("?").firstOrNull() ?: channelPart
            val fallbackOutcome = rawHttpPost(host, port, "/launch/$channelId", 4000L)
            if (fallbackOutcome != null) {
                if (fallbackOutcome in 200..299) return RokuLaunchResult.Ok
                return RokuLaunchResult.Rejected(fallbackOutcome)
            }
            return RokuLaunchResult.Rejected(outcome)
        }
        return RokuLaunchResult.Unreachable
    }

    /**
     * Launches a Roku channel by channel ID with an optional content ID.
     * Tries parameterised launch paths first, then falls back to bare launch.
     */
    suspend fun launch(
        host: String,
        port: Int,
        channelId: String,
        contentId: String?,
        mediaType: String,
    ): RokuLaunchResult {
        rawHttpPost(host, port, "/keypress/Home", 1200L)
        delay(1500)

        val paths = mutableListOf<String>()
        if (contentId != null && contentId.isNotEmpty()) {
            val cid = URLEncoder.encode(contentId, "UTF-8")
            val mt = URLEncoder.encode(mediaType, "UTF-8")
            paths.add("/launch/$channelId?contentId=$cid&mediaType=$mt")
            paths.add("/launch/$channelId?contentID=$cid&MediaType=$mt")
        }
        paths.add("/launch/$channelId")

        var sawForbidden = false
        var lastNonOkStatus: Int? = null

        for (path in paths) {
            val outcome = rawHttpPost(host, port, path, 4000L)
            if (outcome != null) {
                if (outcome in 200..299) return RokuLaunchResult.Ok
                if (outcome == 401 || outcome == 403) {
                    sawForbidden = true
                } else {
                    lastNonOkStatus = outcome
                }
            }
        }

        if (sawForbidden) return RokuLaunchResult.LimitedMode
        if (lastNonOkStatus != null) return RokuLaunchResult.Rejected(lastNonOkStatus)
        return RokuLaunchResult.Unreachable
    }

    /** Sends `keypress/<key>` to the Roku. Best-effort; returns false for non-2xx. */
    suspend fun keypress(host: String, port: Int, key: String): Boolean {
        val code = rawHttpPost(host, port, "/keypress/$key", 2500L)
        return code != null && code in 200..299
    }

    /** Cheap reachability probe — GET /query/device-info, returns true if any response. */
    suspend fun isReachable(host: String, port: Int): Boolean {
        return rawHttpRequest(host, port, "GET", "/query/device-info", 2000L) != null
    }

    /**
     * Extracts the platform-native content ID from a Watchmode web_url.
     * Reproduces the Netflix, Amazon, Hulu, Disney+, Max, Paramount+ and
     * default path-parsing rules from the iOS RokuECPClient.
     */
    fun extractContentId(fromWebUrl: String, platform: String): String? {
        val url = try { URL(fromWebUrl) } catch (_: Exception) { return null }
        val host = url.host?.lowercase() ?: return null
        val path = url.path ?: ""
        val key = platform.lowercase()

        val parts = path.split("/").filter { it.isNotEmpty() }

        if (host.contains("netflix") || key.contains("netflix")) {
            val idx = parts.indexOf("title")
            if (idx >= 0 && idx + 1 < parts.size) return parts[idx + 1]
            return parts.lastOrNull()
        }

        if (host.contains("amazon") || key.contains("prime") || key.contains("amazon")) {
            val idx = parts.indexOf("dp")
            if (idx >= 0 && idx + 1 < parts.size) return parts[idx + 1]
            val detailIdx = parts.indexOf("detail")
            if (detailIdx >= 0 && detailIdx + 1 < parts.size) return parts[detailIdx + 1]
            return parts.lastOrNull()
        }

        if (host.contains("hulu") || key.contains("hulu")) {
            val idx = parts.indexOfFirst { it == "series" || it == "movie" || it == "watch" }
            if (idx >= 0 && idx + 1 < parts.size) return parts[idx + 1]
            return parts.lastOrNull()
        }

        if (host.contains("disneyplus") || key.contains("disney")) {
            return parts.lastOrNull()
        }

        if (host.contains("max.com") || key.contains("hbo") || key.contains(" max")) {
            return parts.lastOrNull()
        }

        if (host.contains("paramount") || key.contains("paramount")) {
            val idx = parts.indexOfFirst { it == "shows" || it == "movies" }
            if (idx >= 0 && idx + 1 < parts.size) return parts[idx + 1]
            return parts.lastOrNull()
        }

        return parts.lastOrNull()
    }

    // MARK: - Raw HTTP (cleartext bypass)

    private suspend fun rawHttpRequest(
        host: String,
        port: Int,
        method: String,
        path: String,
        timeoutMs: Long,
    ): String? = withContext(Dispatchers.IO) {
        withTimeoutOrNull(timeoutMs) {
            try {
                val socket = Socket()
                socket.connect(InetSocketAddress(host, port), timeoutMs.toInt())
                socket.soTimeout = timeoutMs.toInt()

                val request = buildString {
                    append("$method $path HTTP/1.0\r\n")
                    append("Host: $host\r\n")
                    append("User-Agent: GuideStreamTV-ECP/1.0\r\n")
                    if (method == "POST") {
                        append("Content-Length: 0\r\n")
                    }
                    append("Connection: close\r\n\r\n")
                }
                socket.getOutputStream().write(request.toByteArray())
                socket.getOutputStream().flush()

                val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
                val response = StringBuilder()
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    response.append(line).append("\n")
                    if (response.length > 16384) break
                }
                socket.close()
                response.toString()
            } catch (_: Exception) {
                null
            }
        }
    }

    private suspend fun rawHttpPost(
        host: String,
        port: Int,
        path: String,
        timeoutMs: Long,
    ): Int? {
        val response = rawHttpRequest(host, port, "POST", path, timeoutMs) ?: return null
        return parseStatusCode(response)
    }

    private fun parseStatusCode(response: String): Int? {
        val firstLine = response.lines().firstOrNull() ?: return null
        val parts = firstLine.trim().split(" ")
        if (parts.size >= 2) {
            return parts[1].toIntOrNull()
        }
        return null
    }
}
