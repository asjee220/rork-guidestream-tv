package com.rork.guidestreamtvandroid.data

import android.content.Context
import android.content.SharedPreferences

/**
 * Resolves the device's region / language so every TMDB call can be localised.
 *
 * SharedPreferences overrides on "gs_preferred_locale" and "gs_content_region"
 * let the app force a language/region without changing device settings.
 * Both default to null (use device locale). Falls back to "en-US"/"US".
 *
 * Mirrors iOS `ios/Shared/DeviceLocale.swift`.
 */
object DeviceLocale {
    @Volatile private var prefs: SharedPreferences? = null

    fun init(context: Context) {
        if (prefs == null) {
            prefs = context.applicationContext.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)
        }
    }

    /** ISO 3166-1 alpha-2 country code, uppercased. Override → device → "US". */
    val region: String
        get() {
            val override = prefs?.getString("gs_content_region", null)
            if (!override.isNullOrEmpty()) return override.uppercase()
            return java.util.Locale.getDefault().country.ifEmpty { "US" }.uppercase()
        }

    /** BCP-47 language tag for TMDB. Override (expanded) → device → "en-{region}". */
    val tmdbLanguage: String
        get() {
            val override = prefs?.getString("gs_preferred_locale", null)
            if (!override.isNullOrEmpty()) {
                return if (override.contains("-")) override
                else "$override-${region}"
            }
            val lang = java.util.Locale.getDefault().language.ifEmpty { "en" }
            return "$lang-${region}"
        }
}
