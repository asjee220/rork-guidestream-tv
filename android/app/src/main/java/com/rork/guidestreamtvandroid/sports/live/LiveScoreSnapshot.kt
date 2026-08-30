package com.rork.guidestreamtvandroid.sports.live

import kotlinx.serialization.Serializable

/**
 * Everything the ongoing notification and the Glance widget need to render the
 * tracked game, without either of them touching the network.
 *
 * This is Android's stand-in for the iOS Live Activity's split of
 * `SportsActivityAttributes` (fixed for the life of the activity) and
 * `ContentState` (pushed). Android has no equivalent split — an ongoing
 * notification is rebuilt whole on every update — so the two are one object
 * here, and the pushed fields are simply the ones the server overwrites.
 */
@Serializable
data class LiveScoreSnapshot(
    // Fixed for the life of the tracked game.
    val gameId: String,
    val sport: String = "",
    val leagueShort: String = "",
    val homeAbbr: String = "",
    val awayAbbr: String = "",
    val homeShortName: String = "",
    val awayShortName: String = "",
    val homeHex: String = "",
    val awayHex: String = "",
    val broadcast: String = "",
    /** Local row id for the `live_activities` row, so stop() can stamp it. */
    val activityId: String = "",

    // Overwritten by every push.
    val homeScore: Int = 0,
    val awayScore: Int = 0,
    val statusDetail: String = "",
    /** "pre" | "live" | "final". The server pushes "final"; the app's own
     *  SportsGame.state says "post". Both mean the game is over. */
    val state: String = "pre",
) {
    val isFinal: Boolean get() = state == "final" || state == "post"

    /** "Red Sox 1 – Yankees 3" — away first, matching the iOS card's row order. */
    val headline: String
        get() = "${awayShortName.ifBlank { awayAbbr }} $awayScore – " +
            "${homeShortName.ifBlank { homeAbbr }} $homeScore"

    /** "1–3". The status bar chip is tiny; scores only. */
    val criticalText: String get() = "$awayScore–$homeScore"
}
