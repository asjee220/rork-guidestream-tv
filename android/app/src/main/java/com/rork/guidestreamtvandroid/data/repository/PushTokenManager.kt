package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * FCM push token manager — mirrors iOS PushTokenManager.swift.
 * Upserts tokens to the `push_tokens` table (reuses the `apns_token` column
 * for the token string). Caches a pending token when the user is signed out
 * and flushes it on sign-in.
 */
class PushTokenManager private constructor(context: Context) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val prefs = context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)

    private var pendingToken: String? = null

    companion object {
        @Volatile private var instance: PushTokenManager? = null
        fun init(context: Context): PushTokenManager =
            instance ?: synchronized(this) {
                instance ?: PushTokenManager(context.applicationContext).also { instance = it }
            }
        fun get(): PushTokenManager =
            instance ?: error("PushTokenManager not initialized")
    }

    /** Saves (upserts) the given FCM token to Supabase. Caches it as pending
     *  until the upsert succeeds so it can be retried after sign-in. */
    fun saveToken(token: String) {
        pendingToken = token
        val auth = AuthViewModel.get()
        val userId = auth.currentUserId ?: return
        val deviceId = DeviceIdentity.get().deviceId
        scope.launch {
            try {
                val payload = buildJsonObject {
                    put("apns_token", token)
                    put("user_id", userId)
                    put("device_id", deviceId)
                    put("platform", "android")
                }
                SupabaseManager.client.postgrest
                    .from("push_tokens")
                    .upsert(payload) { onConflict = "apns_token" }
                pendingToken = null
            } catch (_: Exception) {
                // Silent-fail — will be retried by flushPendingToken
            }
        }
    }

    /** Re-attempts saving the pending token when a user now exists. */
    fun flushPendingToken() {
        val token = pendingToken ?: return
        val auth = AuthViewModel.get()
        val userId = auth.currentUserId ?: return
        val deviceId = DeviceIdentity.get().deviceId
        scope.launch {
            try {
                val payload = buildJsonObject {
                    put("apns_token", token)
                    put("user_id", userId)
                    put("device_id", deviceId)
                    put("platform", "android")
                }
                SupabaseManager.client.postgrest
                    .from("push_tokens")
                    .upsert(payload) { onConflict = "apns_token" }
                pendingToken = null
            } catch (_: Exception) {}
        }
    }

    /** Re-saves the cached token (used after a new sign-in). */
    fun resaveCachedToken() {
        val token = prefs.getString("gs.fcmToken", null) ?: return
        saveToken(token)
    }

    /** Clears the token row for the current user on sign-out. */
    fun clearToken() {
        val auth = AuthViewModel.get()
        val userId = auth.currentUserId ?: return
        scope.launch {
            try {
                SupabaseManager.client.postgrest
                    .from("push_tokens")
                    .delete { filter { eq("user_id", userId) } }
            } catch (_: Exception) {}
        }
        pendingToken = null
    }

    /** Caches the token locally so it can be re-saved after sign-in. */
    fun cacheToken(token: String) {
        prefs.edit().putString("gs.fcmToken", token).apply()
    }
}
