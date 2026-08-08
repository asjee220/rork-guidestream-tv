package com.rork.guidestreamtvandroid.data.repository

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * FCM push token manager — mirrors iOS PushTokenManager.swift.
 * Upserts tokens to the `push_tokens` table (reuses the `apns_token` column
 * for the token string; `device_type = "android"` routes delivery to FCM
 * instead of APNs). Caches a pending token when the user is signed out and
 * flushes it on sign-in.
 *
 * The live table has exactly five columns — id, user_id, apns_token,
 * device_type, created_at — so payloads must contain only user_id,
 * apns_token, and device_type. The upsert conflict target stays on the
 * `push_tokens_apns_token_key` unique constraint.
 */
class PushTokenManager private constructor(context: Context) {

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val prefs = context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)

    private var pendingToken: String? = null

    companion object {
        private const val TAG = "GSPush"

        @Volatile private var instance: PushTokenManager? = null
        fun init(context: Context): PushTokenManager =
            instance ?: synchronized(this) {
                instance ?: PushTokenManager(context.applicationContext).also { instance = it }
            }
        fun get(): PushTokenManager =
            instance ?: error("PushTokenManager not initialized")
    }

    /**
     * Fetches the current FCM registration token and saves it, but only when
     * notification permission is already granted — this method never triggers
     * a permission dialog. Mirrors iOS `refreshRegistrationIfAuthorized`.
     * Idempotent: the `apns_token` conflict target refreshes the existing row
     * rather than inserting duplicates, so repeated calls (onResume, repeated
     * grants) are safe.
     */
    fun registerIfPermitted() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                appContext,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                Log.d(TAG, "registerIfPermitted: POST_NOTIFICATIONS not granted — skipping")
                return
            }
        }
        try {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    val token = task.result
                    if (token.isNullOrEmpty()) {
                        Log.w(TAG, "registerIfPermitted: FCM returned a null/empty token")
                    } else {
                        Log.d(TAG, "registerIfPermitted: FCM token fetched — caching and saving")
                        cacheToken(token)
                        saveToken(token)
                    }
                } else {
                    Log.e(TAG, "registerIfPermitted: FCM token fetch failed: ${task.exception?.message}")
                }
            }
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            Log.e(TAG, "registerIfPermitted: FirebaseMessaging unavailable: ${e.message}")
        }
    }

    /** Saves (upserts) the given FCM token to Supabase. Always caches the
     *  token first — mirroring iOS, which writes to UserDefaults before any
     *  auth check — so a token received while signed out survives process
     *  death. Skips the upsert without error when no user is signed in
     *  (push_tokens RLS requires auth.uid() = user_id anyway). */
    fun saveToken(token: String) {
        cacheToken(token)
        pendingToken = token
        val auth = AuthViewModel.get()
        val userId = auth.currentUserId
        if (userId == null) {
            Log.d(TAG, "saveToken: no signed-in user — token cached, upsert deferred")
            return
        }
        scope.launch {
            try {
                val payload = buildJsonObject {
                    put("user_id", userId)
                    put("apns_token", token)
                    put("device_type", "android")
                }
                SupabaseManager.client.postgrest
                    .from("push_tokens")
                    .upsert(payload) { onConflict = "apns_token" }
                pendingToken = null
                Log.d(TAG, "saveToken: upsert succeeded for user=$userId device_type=android")
            } catch (e: Throwable) {
                if (e is CancellationException) throw e
                // Kept non-fatal — will be retried by flushPendingToken.
                Log.e(TAG, "saveToken: upsert failed for user=$userId: ${e.message}")
            }
        }
    }

    /** Re-attempts saving the pending token when a user now exists. */
    fun flushPendingToken() {
        val token = pendingToken ?: return
        val auth = AuthViewModel.get()
        val userId = auth.currentUserId ?: return
        scope.launch {
            try {
                val payload = buildJsonObject {
                    put("user_id", userId)
                    put("apns_token", token)
                    put("device_type", "android")
                }
                SupabaseManager.client.postgrest
                    .from("push_tokens")
                    .upsert(payload) { onConflict = "apns_token" }
                pendingToken = null
                Log.d(TAG, "flushPendingToken: upsert succeeded for user=$userId device_type=android")
            } catch (e: Throwable) {
                if (e is CancellationException) throw e
                Log.e(TAG, "flushPendingToken: upsert failed for user=$userId: ${e.message}")
            }
        }
    }

    /** Re-saves the cached token (used after a new sign-in). */
    fun resaveCachedToken() {
        val token = prefs.getString("gs.fcmToken", null)
        if (token == null) {
            Log.d(TAG, "resaveCachedToken: no cached token")
            return
        }
        Log.d(TAG, "resaveCachedToken: re-saving cached token")
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
                Log.d(TAG, "clearToken: deleted push_tokens rows for user=$userId")
            } catch (e: Throwable) {
                if (e is CancellationException) throw e
                Log.w(TAG, "clearToken: delete failed for user=$userId: ${e.message}")
            }
        }
        pendingToken = null
    }

    /** Caches the token locally so it can be re-saved after sign-in. */
    fun cacheToken(token: String) {
        prefs.edit().putString("gs.fcmToken", token).apply()
    }
}
