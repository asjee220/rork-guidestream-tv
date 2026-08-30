package com.rork.guidestreamtvandroid.data

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build

/**
 * Where a sports broadcast should open on Android.
 *
 * [appPackage] is the broadcaster's Play Store package, used to launch the app
 * directly when it does not claim [webUrl] as a verified App Link. Every
 * package here was checked against its live Play Store listing; a broadcaster
 * whose app could not be confirmed carries a null package and opens the web
 * page rather than a guess.
 */
data class BroadcastTarget(
    val appPackage: String?,
    val webUrl: String,
)

/**
 * Opens the broadcaster's app for a live game (GUI-77).
 *
 * The sports sheet's Watch button used to fire a Google search URL, so it
 * always landed in a browser even when the ESPN or FOX Sports app was
 * installed. This is the Android counterpart to the sports-broadcaster branch
 * of iOS `StreamingDeepLinker.resolve`, but the open chain differs because the
 * mechanism does: iOS forces a universal link with `universalLinksOnly`,
 * Android has App Links plus a package launch.
 *
 * Live broadcasters do not publish game-specific deep links, so the best
 * available outcome is the app's own home or watch screen — the same ceiling
 * iOS hits. Landing in the app at all is the fix.
 */
object SportsBroadcastLinks {

    /**
     * Three-step chain, each step degrading to the next:
     *
     * 1. **App Link** — `ACTION_VIEW` on the https URL with
     *    `FLAG_ACTIVITY_REQUIRE_NON_BROWSER`, which throws rather than falling
     *    into a browser when no installed app claims the domain. The only step
     *    that can land on a specific page.
     * 2. **Package launch** — the broadcaster's launcher activity, so the app
     *    opens and the user is one tap from the game.
     * 3. **Browser** — the web page, which is where every tap used to end up.
     *
     * Returns false only when even the browser could not be opened.
     */
    fun open(context: Context, broadcast: String, gameTitle: String): Boolean {
        val target = target(broadcast, gameTitle)
        if (openAsAppLink(context, target.webUrl)) return true
        if (target.appPackage != null && launchPackage(context, target.appPackage)) return true
        return openInBrowser(context, target.webUrl)
    }

    /**
     * `FLAG_ACTIVITY_REQUIRE_NON_BROWSER` is API 30+. Below that there is no
     * way to ask for "an app but not a browser", so the step is skipped and the
     * package launch does the work.
     */
    private fun openAsAppLink(context: Context, url: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        return try {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    .addFlags(Intent.FLAG_ACTIVITY_REQUIRE_NON_BROWSER)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Needs the package listed in the manifest's `<queries>` block — without
     * visibility `getLaunchIntentForPackage` returns null on Android 11+ even
     * when the app is installed.
     */
    private fun launchPackage(context: Context, packageName: String): Boolean {
        return try {
            val intent = context.packageManager.getLaunchIntentForPackage(packageName)
                ?: return false
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openInBrowser(context: Context, url: String): Boolean {
        return try {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Maps a broadcast name from the ESPN feed ("ESPN2", "FS1", "NBC",
     * "Peacock", "NFL Network"...) onto an app and a web page. Substring
     * matching on a lowercased key, mirroring the iOS resolver so both
     * platforms route the same broadcast to the same place.
     */
    fun target(broadcast: String, gameTitle: String): BroadcastTarget {
        val key = broadcast.lowercase()

        // ESPN family, and ABC — Disney routes ABC's sports through ESPN.
        if (key.contains("espn") || key.contains("abc") || key.contains("sec network") ||
            key.contains("acc network") || key.contains("longhorn")
        ) {
            return BroadcastTarget("com.espn.score_center", "https://www.espn.com/watch/")
        }
        // FOX broadcast and the FS channels.
        if (key.contains("fox") || key.contains("fs1") || key.contains("fs2")) {
            return BroadcastTarget("com.foxsports.android", "https://www.foxsports.com/live")
        }
        // NBC's sports coverage moved into Peacock — the standalone NBC Sports
        // app is gone from Play, so NBC, USA and CNBC all land in Peacock.
        if (key.contains("nbc") || key.contains("peacock") || key.contains("usa network") ||
            key.contains("cnbc") || key.contains("golf channel")
        ) {
            return BroadcastTarget("com.peacocktv.peacockandroid", "https://www.peacocktv.com/sports")
        }
        // Paramount+ carries CBS's live sports; the CBS Sports app is scores
        // and news, so the streaming destination wins for a watch button.
        if (key.contains("paramount")) {
            return BroadcastTarget("com.cbs.app", "https://www.paramountplus.com/live-tv/")
        }
        if (key.contains("cbs")) {
            return BroadcastTarget("com.handmark.sportcaster", "https://www.cbssports.com/live/")
        }
        // TNT / TBS / truTV — Warner's sports stream on HBO Max, with Bleacher
        // Report as the companion. Max is where the game actually plays.
        if (key.contains("tnt") || key.contains("tbs") || key.contains("trutv") ||
            key.contains("max")
        ) {
            return BroadcastTarget("com.wbd.stream", "https://play.max.com/")
        }
        if (key.contains("bleacher")) {
            return BroadcastTarget(
                "com.bleacherreport.android.teamstream", "https://bleacherreport.com/live"
            )
        }
        // League-owned channels and streaming tiers.
        if (key.contains("nfl")) {
            return BroadcastTarget("com.gotv.nflgamecenter.us.lite", "https://www.nfl.com/plus/")
        }
        if (key.contains("nba")) {
            return BroadcastTarget("com.nbaimd.gametime.nba2011", "https://www.nba.com/watch")
        }
        if (key.contains("mlb")) {
            return BroadcastTarget(
                "com.bamnetworks.mobile.android.gameday.atbat", "https://www.mlb.com/tv"
            )
        }
        if (key.contains("nhl")) {
            return BroadcastTarget("com.nhl.gc1112.free", "https://www.nhl.com/tv")
        }
        // Aggregators.
        if (key.contains("fubo")) {
            return BroadcastTarget("tv.fubo.mobile", "https://www.fubo.tv/welcome")
        }
        if (key.contains("sling")) {
            return BroadcastTarget("com.sling", "https://www.sling.com/")
        }
        if (key.contains("dazn")) {
            return BroadcastTarget("com.dazn", "https://www.dazn.com/")
        }
        if (key.contains("prime") || key.contains("amazon")) {
            return BroadcastTarget(
                "com.amazon.avod.thirdpartyclient", "https://www.primevideo.com/"
            )
        }

        // Unknown broadcaster: the search fallback this file exists to stop
        // being the only outcome. No package — nothing to guess at.
        val q = Uri.encode("watch $gameTitle on $broadcast live")
        return BroadcastTarget(null, "https://www.google.com/search?q=$q")
    }
}
