package com.rork.guidestreamtvandroid.data.repository

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.content.SharedPreferences
import android.util.Log
import com.rork.guidestreamtvandroid.data.local.DeviceSessionService
import com.google.android.play.core.review.ReviewManagerFactory
import java.util.concurrent.TimeUnit

/**
 * In-app review gate — mirrors iOS ReviewPromptManager.swift.
 *
 * Counters are stored per install, NOT per user id: the large majority of
 * installs never sign in, so keying on a user would exclude them entirely.
 *
 * Nothing here ever prompts mid-task. A qualifying action only *arms* the
 * prompt; it is presented on the next return to the app (onResume), which is
 * the moment the user has just come back from a streaming app or finished
 * something and is not being interrupted.
 */
object ReviewPromptManager {

    enum class Trigger(val value: String) {
        DEEP_LINK_RETURN("deeplink_return"),
        WATCHED_MILESTONE("watched_milestone"),
        ALERT_TO_WATCH("alert_to_watch"),
        CAST_STARTED("cast_started"),
        RETURN_VISIT("return_visit"),
    }

    private const val PREFS = "gs_review_prompt"
    private const val KEY_FIRST_LAUNCH = "firstLaunch"
    private const val KEY_SESSIONS = "sessions"
    private const val KEY_DEEP_LINKS = "deepLinks"
    private const val KEY_WATCHED = "watched"
    private const val KEY_SHOWN_DATES = "shownDates"
    private const val KEY_ARMED_DEEP_LINK = "armedDeepLink"
    private const val KEY_ACTIVE_DAYS = "activeDays"
    private const val KEY_LAST_ACTIVE_DAY = "lastActiveDay"

    private const val MIN_INSTALL_DAYS = 3
    private const val MIN_SESSIONS = 3
    private const val DEEP_LINK_THRESHOLD = 2
    private const val WATCHED_THRESHOLD = 5
    /** Separate calendar days the app has been opened, for [Trigger.RETURN_VISIT]. */
    private const val ACTIVE_DAY_THRESHOLD = 3
    // 90 days is the industry floor between prompts, and the annual cap now
    // matches what the platform allows rather than self-throttling below it —
    // over quota the flow silently does nothing, so a held-back prompt is
    // simply a forfeited one. Mirrors iOS.
    private const val COOLDOWN_DAYS = 90
    private const val MAX_PER_YEAR = 3

    private lateinit var prefs: SharedPreferences

    /** Set when a qualifying action fires; consumed by [maybePresent]. */
    @Volatile private var pendingTrigger: Trigger? = null

    fun init(context: Context) {
        prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY_FIRST_LAUNCH)) {
            prefs.edit().putLong(KEY_FIRST_LAUNCH, System.currentTimeMillis()).apply()
        }
    }

    private val ready: Boolean get() = ::prefs.isInitialized

    // MARK: - Signals

    fun noteSessionStarted() {
        if (!ready) return
        bump(KEY_SESSIONS)
    }

    /** A deep link into a streaming app. Arms, but never prompts right now —
     *  the user is about to leave; the prompt waits for their return. */
    fun noteDeepLinkFired() {
        if (!ready) return
        val count = bump(KEY_DEEP_LINKS)
        if (count >= DEEP_LINK_THRESHOLD) {
            prefs.edit().putBoolean(KEY_ARMED_DEEP_LINK, true).apply()
        }
    }

    fun noteWatchedToggled() {
        if (!ready) return
        val count = bump(KEY_WATCHED)
        if (count >= WATCHED_THRESHOLD && count % WATCHED_THRESHOLD == 0) {
            consider(Trigger.WATCHED_MILESTONE)
        }
    }

    fun noteCastStarted() {
        if (!ready) return
        consider(Trigger.CAST_STARTED)
    }

    fun noteAlertOpened() {
        if (!ready) return
        prefs.edit().putBoolean(KEY_ARMED_DEEP_LINK, true).apply()
    }

    // MARK: - Presentation

    /** Call from Activity.onResume. Presents at most one prompt. */
    fun maybePresent(activity: Activity) {
        if (!ready) return
        noteActiveDay()
        if (prefs.getBoolean(KEY_ARMED_DEEP_LINK, false)) {
            prefs.edit().putBoolean(KEY_ARMED_DEEP_LINK, false).apply()
            consider(Trigger.DEEP_LINK_RETURN)
        } else if (prefs.getInt(KEY_ACTIVE_DAYS, 0) >= ACTIVE_DAY_THRESHOLD) {
            // Coming back on a third separate day IS the satisfaction signal.
            // This app is a guide — its value is delivered by looking
            // something up and leaving — so the prompt is not gated on a deep
            // link or a watched-toggle first. Mirrors iOS.
            consider(Trigger.RETURN_VISIT)
        }
        val trigger = pendingTrigger ?: return
        pendingTrigger = null
        launchFlow(activity, trigger)
    }

    private fun consider(trigger: Trigger) {
        if (!isEligible) return
        pendingTrigger = trigger
    }

    private val isEligible: Boolean
        get() {
            val firstLaunch = prefs.getLong(KEY_FIRST_LAUNCH, System.currentTimeMillis())
            val installDays = TimeUnit.MILLISECONDS.toDays(System.currentTimeMillis() - firstLaunch)
            if (installDays < MIN_INSTALL_DAYS) return false
            if (sessionsForGate < MIN_SESSIONS) return false
            // Never on top of a forced-update or update-nudge sheet.
            if (runCatching { AppUpdateGate.get().prompt }.getOrNull() != null) return false

            val shown = shownDates()
            val now = System.currentTimeMillis()
            val yearAgo = now - TimeUnit.DAYS.toMillis(365)
            if (shown.count { it > yearAgo } >= MAX_PER_YEAR) return false
            val last = shown.maxOrNull() ?: return true
            return TimeUnit.MILLISECONDS.toDays(now - last) >= COOLDOWN_DAYS
        }

    /**
     * The local counter starts at zero on the launch where this shipped, so it
     * under-reports a long-standing install. DeviceSessionService keeps the
     * same per-install number from the day the app was installed — take the
     * larger, so an update does not make a returning user start over.
     */
    private val sessionsForGate: Int
        get() = maxOf(
            prefs.getInt(KEY_SESSIONS, 0),
            runCatching { DeviceSessionService.get().sessionCount }.getOrDefault(0),
        )

    /** One increment per calendar day the app is opened. */
    private fun noteActiveDay() {
        val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
            .format(java.util.Date())
        if (prefs.getString(KEY_LAST_ACTIVE_DAY, null) == today) return
        prefs.edit().putString(KEY_LAST_ACTIVE_DAY, today).apply()
        bump(KEY_ACTIVE_DAYS)
    }

    private fun launchFlow(activity: Activity, trigger: Trigger) {
        val manager = ReviewManagerFactory.create(activity)
        manager.requestReviewFlow().addOnCompleteListener { request ->
            if (!request.isSuccessful) {
                Log.w("GSReview", "requestReviewFlow failed: ${request.exception?.message}")
                return@addOnCompleteListener
            }
            manager.launchReviewFlow(activity, request.result).addOnCompleteListener {
                // Play never tells us whether the sheet was actually shown or
                // whether the user rated. Record the attempt either way — that
                // is what the quota and the cooldown have to be based on.
                recordShown(trigger)
            }
        }
    }

    private fun recordShown(trigger: Trigger) {
        val dates = (shownDates() + System.currentTimeMillis()).takeLast(10)
        prefs.edit().putString(KEY_SHOWN_DATES, dates.joinToString(",")).apply()
        runCatching {
            WatchIntentLogger.get().log(
                eventType = WatchIntentLogger.IntentEventType.REVIEW_PROMPT_REQUESTED,
                metadata = mapOf(
                    "trigger" to trigger.value,
                    "deep_links" to prefs.getInt(KEY_DEEP_LINKS, 0),
                    "watched" to prefs.getInt(KEY_WATCHED, 0),
                    "sessions" to sessionsForGate,
                    "active_days" to prefs.getInt(KEY_ACTIVE_DAYS, 0),
                ),
            )
        }
    }

    // MARK: - Helpers

    private fun shownDates(): List<Long> =
        prefs.getString(KEY_SHOWN_DATES, "")
            .orEmpty()
            .split(",")
            .mapNotNull { it.trim().toLongOrNull() }

    private fun bump(key: String): Int {
        val next = prefs.getInt(key, 0) + 1
        prefs.edit().putInt(key, next).apply()
        return next
    }

    private const val PACKAGE = "com.rork.guidestreamtvandroid"

    /**
     * Opens the Play Store listing for the explicit "Rate" row.
     *
     * Deliberately NOT [launchReviewFlow]: Play's in-app sheet is quota'd and
     * silently does nothing once spent, so a button wired to it would look
     * broken exactly when a user has decided to leave a review. The listing
     * always works.
     *
     * Tries the Play Store app first (`market://`) and falls back to the web
     * listing on devices without it.
     */
    fun openStoreListing(context: Context) {
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$PACKAGE"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(market)
        } catch (_: ActivityNotFoundException) {
            val web = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$PACKAGE"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            runCatching { context.startActivity(web) }
        }
    }
}
