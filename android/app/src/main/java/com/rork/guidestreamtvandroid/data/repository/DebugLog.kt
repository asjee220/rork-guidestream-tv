package com.rork.guidestreamtvandroid.data.repository

import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Fire-and-forget diagnostics logger writing to the existing `public.debug_logs`
 * table. Mirrors the Supabase insert convention used by [WatchIntentLogger]
 * (`SupabaseManager.client.postgrest.from(...).insert(payload)`).
 *
 * Every call launches on [Dispatchers.IO], swallows every exception (including
 * offline and RLS rejections), and never throws or blocks the caller. It only
 * writes to columns that already exist on the table; it never creates a table
 * or invents columns.
 */
object DebugLog {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Writes a single diagnostics row. All parameters are optional beyond
     * [event] so callers only fill the columns they care about; user/device
     * identity is resolved automatically the same way [WatchIntentLogger] does.
     */
    fun log(
        event: String,
        platform: String? = null,
        title: String? = null,
        contentUrl: String? = null,
        deviceName: String? = null,
        targetName: String? = null,
        matched: Boolean? = null,
    ) {
        val userId = try { AuthViewModel.get().currentUserId } catch (_: Throwable) { null }
        val deviceId = try { DeviceIdentity.get().deviceId } catch (_: Throwable) { null }

        scope.launch {
            try {
                val payload = buildJsonObject {
                    put("event", event)
                    if (userId != null) put("user_id", userId)
                    if (deviceId != null) put("device_id", deviceId)
                    put("device_kind", "phone")
                    if (platform != null) put("platform", platform)
                    if (title != null) put("title", title)
                    if (contentUrl != null) put("content_url", contentUrl)
                    if (deviceName != null) put("device_name", deviceName)
                    if (targetName != null) put("target_name", targetName)
                    if (matched != null) put("matched", matched)
                }
                SupabaseManager.client.postgrest
                    .from("debug_logs")
                    .insert(payload)
            } catch (_: Throwable) {
                // Diagnostics must never surface an error or block playback.
            }
        }
    }
}
