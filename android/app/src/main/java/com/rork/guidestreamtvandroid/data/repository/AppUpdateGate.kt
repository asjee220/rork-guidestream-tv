package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.rork.guidestreamtvandroid.data.remote.RemoteConfigService

/**
 * Decides what — if anything — to show the user about app versions when the
 * app opens (GUI-43). Mirrors iOS `AppUpdateGate`.
 *
 * Three states, one system, in strict precedence:
 *
 *  - [AppUpdatePrompt.Required]  installed < `min`: a blocking screen with no
 *    dismiss. The only lever that can retire a client talking to an endpoint
 *    we have since changed, which is the operational reason this exists.
 *  - [AppUpdatePrompt.Available] installed < `latest`: a dismissible sheet,
 *    shown at most once a week per released version so a user who is happy
 *    where they are is not nagged.
 *  - [AppUpdatePrompt.WhatsNew]  installed > the version last seen: the
 *    release notes, once, after the update already happened. No store trip.
 *
 * Everything is driven by one `app_update` row in `app_config`, which both
 * platforms already read and cache on launch, so shipping a floor is an edit
 * to one row rather than a release.
 *
 * A first-ever install records its version and shows nothing: there is no
 * "what's new" for someone who has not been here before.
 */
sealed interface AppUpdatePrompt {
    data class Required(val storeUrl: String?) : AppUpdatePrompt
    data class Available(
        val version: String,
        val storeUrl: String?,
        val notes: List<String>,
    ) : AppUpdatePrompt

    data class WhatsNew(
        val version: String,
        val title: String,
        val notes: List<String>,
    ) : AppUpdatePrompt
}

class AppUpdateGate private constructor(private val context: Context) {

    companion object {
        @Volatile private var instance: AppUpdateGate? = null

        fun init(context: Context): AppUpdateGate =
            instance ?: synchronized(this) {
                instance ?: AppUpdateGate(context.applicationContext).also { instance = it }
            }

        /** Throws only if [init] was never called from Application.onCreate(). */
        fun get(): AppUpdateGate = instance
            ?: error("AppUpdateGate.init(context) must run before get()")

        private const val PREFS_NAME = "gs_prefs"
        private const val LAST_SEEN_KEY = "gs.appUpdate.lastSeenVersion"
        private const val NUDGED_KEY = "gs.appUpdate.lastNudge."
        private const val NOTES_SHOWN_KEY = "gs.appUpdate.notesShownFor"

        /** A user who dismissed the nudge should not see it again for a week. */
        private const val NUDGE_INTERVAL_MS = 7L * 24 * 60 * 60 * 1000

        /**
         * Compares dotted numeric versions component by component, tolerating
         * different component counts ("1.1" < "1.1.1") and non-numeric junk,
         * which sorts as zero rather than throwing the comparison out.
         */
        fun compare(lhs: String, rhs: String): Int {
            val l = lhs.split(".").map { part -> part.filter { it.isDigit() }.toIntOrNull() ?: 0 }
            val r = rhs.split(".").map { part -> part.filter { it.isDigit() }.toIntOrNull() ?: 0 }
            for (i in 0 until maxOf(l.size, r.size)) {
                val a = l.getOrElse(i) { 0 }
                val b = r.getOrElse(i) { 0 }
                if (a != b) return a.compareTo(b)
            }
            return 0
        }
    }

    /** Non-null when something should be on screen. MainScreen binds to it. */
    var prompt by mutableStateOf<AppUpdatePrompt?>(null)
        private set

    /**
     * True while a required update is on screen — the host renders this as a
     * full-screen, non-dismissible surface rather than a bottom sheet.
     */
    val isBlocking: Boolean get() = prompt is AppUpdatePrompt.Required

    private val prefs by lazy { context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }

    /** The running app's version name ("1.0.21"). */
    val currentVersion: String
        get() = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0"
        } catch (_: Exception) {
            "0"
        }

    /**
     * Evaluates the three states against the loaded remote config. Safe to
     * call on every launch; it is the caller's only entry point.
     */
    fun evaluate(config: RemoteConfigService.RemoteAppUpdate? = RemoteConfigService.appUpdateConfig()) {
        val current = currentVersion
        val previous = prefs.getString(LAST_SEEN_KEY, null)
        // Record first so a crash inside the presentation cannot replay a
        // What's New sheet on every launch.
        prefs.edit().putString(LAST_SEEN_KEY, current).apply()

        val platform = config?.android ?: return
        val storeUrl = platform.url?.takeIf { it.isNotBlank() }
        val notes = config.notes?.items.orEmpty()

        // 1. Hard floor.
        val min = platform.min
        if (!min.isNullOrBlank() && compare(current, min) < 0) {
            prompt = AppUpdatePrompt.Required(storeUrl)
            return
        }

        // 2. Newer version available — dismissible, rate limited.
        val latest = platform.latest
        if (!latest.isNullOrBlank() && compare(current, latest) < 0) {
            if (shouldNudge(latest)) {
                prompt = AppUpdatePrompt.Available(latest, storeUrl, notes)
            }
            return
        }

        // 3. The user just updated into this version. Requires a recorded
        // previous version, so a fresh install shows nothing.
        if (!previous.isNullOrBlank() &&
            compare(previous, current) < 0 &&
            notes.isNotEmpty() &&
            !notesShown(current)
        ) {
            markNotesShown(current)
            prompt = AppUpdatePrompt.WhatsNew(
                version = current,
                title = config.notes?.title?.takeIf { it.isNotBlank() } ?: "What's new",
                notes = notes,
            )
        }
    }

    /**
     * Dismisses whichever dismissible prompt is showing. A required update
     * ignores this — there is nothing to dismiss to.
     */
    fun dismissCurrent() {
        when (val p = prompt) {
            is AppUpdatePrompt.Available -> {
                prefs.edit().putLong(NUDGED_KEY + p.version, System.currentTimeMillis()).apply()
                prompt = null
            }
            is AppUpdatePrompt.WhatsNew -> prompt = null
            else -> Unit
        }
    }

    private fun shouldNudge(version: String): Boolean {
        val last = prefs.getLong(NUDGED_KEY + version, 0L)
        if (last == 0L) return true
        return System.currentTimeMillis() - last >= NUDGE_INTERVAL_MS
    }

    private fun notesShown(version: String): Boolean =
        prefs.getStringSet(NOTES_SHOWN_KEY, emptySet())?.contains(version) == true

    private fun markNotesShown(version: String) {
        // Only the recent tail matters; the set is a "have we shown this"
        // check, not history.
        val shown = prefs.getStringSet(NOTES_SHOWN_KEY, emptySet()).orEmpty().toMutableList()
        if (shown.contains(version)) return
        shown.add(version)
        prefs.edit()
            .putStringSet(NOTES_SHOWN_KEY, shown.takeLast(10).toSet())
            .apply()
    }
}
