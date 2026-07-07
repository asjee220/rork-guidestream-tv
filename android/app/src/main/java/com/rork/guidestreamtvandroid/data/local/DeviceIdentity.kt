package com.rork.guidestreamtvandroid.data.local

import android.annotation.SuppressLint
import android.content.Context
import android.provider.Settings
import java.util.UUID

/**
 * Stable per-device identifier — mirrors iOS DeviceIdentity.swift.
 * Persists across launches in DataStore. Falls back to ANDROID_ID on first
 * launch when nothing is cached. Always a valid UUID string.
 */
class DeviceIdentity private constructor(context: Context) {

    val deviceId: String
    val isFirstLaunch: Boolean

    companion object {
        @Volatile private var instance: DeviceIdentity? = null

        fun init(context: Context): DeviceIdentity =
            instance ?: synchronized(this) {
                instance ?: DeviceIdentity(context.applicationContext).also { instance = it }
            }

        fun get(): DeviceIdentity =
            instance ?: error("DeviceIdentity not initialized — call init() in Application.onCreate()")
    }

    init {
        val prefs = context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)
        val cached = prefs.getString("gs.deviceId", null)
        if (!cached.isNullOrEmpty()) {
            deviceId = cached
            isFirstLaunch = false
        } else {
            // Use ANDROID_ID (stable per-app-signing-key per-device on Android 8+)
            // wrapped in a UUID namespace for consistency with the iOS uuid column.
            @SuppressLint("HardwareIds")
            val androidId = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ANDROID_ID,
            )
            val fresh = if (!androidId.isNullOrEmpty()) {
                UUID.nameUUIDFromBytes(androidId.toByteArray()).toString()
            } else {
                UUID.randomUUID().toString()
            }
            prefs.edit().putString("gs.deviceId", fresh).apply()
            deviceId = fresh
            isFirstLaunch = true
        }
    }
}
