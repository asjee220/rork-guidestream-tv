package com.rork.guidestreamtvandroid.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.layout.wrapContentHeight
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.rork.guidestreamtvandroid.MainActivity
import com.rork.guidestreamtvandroid.sports.live.LiveScoreSnapshot
import kotlinx.serialization.json.Json

/**
 * Guide Stream TV home-screen widget — mirrors iOS GuideStreamWidget.swift.
 * Renders the unified "Next Up" feed (live, new, soon, out) across small,
 * medium, and large sizes. Each row is individually tappable via a
 * guidestream:// deep link that opens the app on that title's detail screen.
 * Refresh policy: 30 minutes.
 */
class GuideStreamWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val prefs = context.getSharedPreferences("gs_widget_payload", Context.MODE_PRIVATE)
        val service = WidgetDataService.get()
        val payload = service.loadPayload()
        // Read straight from the controller's own prefs rather than through the
        // singleton: provideGlance can run in the widget host's process, where
        // GuideStreamTVApp.onCreate has not necessarily run.
        val live = readTrackedGame(context)

        provideContent {
            GlanceTheme {
                WidgetContent(payload, context, live)
            }
        }
    }

    /** The game the user is tracking, or null. Mirrors the notification. */
    private fun readTrackedGame(context: Context): LiveScoreSnapshot? {
        val raw = context
            .getSharedPreferences("gs_live_score", Context.MODE_PRIVATE)
            .getString("gs.liveScore.snapshot.v1", null) ?: return null
        return try {
            Json { ignoreUnknownKeys = true }.decodeFromString<LiveScoreSnapshot>(raw)
        } catch (_: Exception) {
            null
        }
    }

    @Composable
    private fun WidgetContent(
        payload: WidgetPayload,
        context: Context,
        live: LiveScoreSnapshot?,
    ) {
        val size = LocalSize.current
        val isSmall = size.width < 200.dp
        val isMedium = size.width >= 200.dp && size.width < 300.dp

        // A tracked game outranks the feed: it is the thing the user explicitly
        // asked to watch, and it is the only part of the widget that changes
        // minute to minute. On the small size it takes the whole widget — there
        // is no room to show both and the score is what was asked for.
        if (live != null && isSmall) {
            Box(
                modifier = GlanceModifier
                    .fillMaxSize()
                    .background(Color(red = 0x04, green = 0x09, blue = 0x0F))
                    .clickable(actionStartActivity<MainActivity>()),
            ) {
                LiveScoreCard(live, compact = true)
            }
            return
        }

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(Color(red = 0x04, green = 0x09, blue = 0x0F))
                .clickable(actionStartActivity<MainActivity>()),
        ) {
            if (live != null) {
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    LiveScoreCard(live, compact = false)
                    Box(modifier = GlanceModifier.fillMaxSize()) {
                        if (isMedium) {
                            MediumWidget(payload, context)
                        } else {
                            LargeWidget(payload, context)
                        }
                    }
                }
                return@Box
            }
            if (isSmall) {
                SmallWidget(payload)
            } else if (isMedium) {
                MediumWidget(payload, context)
            } else {
                LargeWidget(payload, context)
            }
        }
    }

    private fun kindColor(kind: String): Color = when (kind) {
        "live" -> Color(red = 0xFF, green = 0x3B, blue = 0x30)
        "new" -> Color(red = 0x00, green = 0x9E, blue = 0x8A)
        "soon" -> Color(red = 0x1A, green = 0x6F, blue = 0xE8)
        "out" -> Color(red = 0xF5, green = 0x82, blue = 0x1F)
        else -> Color(red = 0xF5, green = 0x82, blue = 0x1F)
    }

    /**
     * The tracked game, drawn to echo the notification and the iOS lock-screen
     * card: league chip, away over home with scores, status line. Deliberately
     * no controls — Glance actions on a home-screen widget cannot end a
     * notification cleanly, and the notification's own Stop action is always
     * one glance away.
     */
    @Composable
    private fun LiveScoreCard(live: LiveScoreSnapshot, compact: Boolean) {
        val orange = Color(red = 0xF5, green = 0x82, blue = 0x1F)
        val liveOrange = Color(red = 0xFF, green = 0x9F, blue = 0x0A)
        val muted = Color(red = 0xFF, green = 0xFF, blue = 0xFF)
        val isLive = live.state == "live"

        Column(
            modifier = GlanceModifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = if (compact) 12.dp else 10.dp),
        ) {
            Text(
                text = live.leagueShort.uppercase(),
                style = TextStyle(
                    color = ColorProvider(orange),
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
            Spacer(GlanceModifier.height(if (compact) 8.dp else 6.dp))
            ScoreLine(live.awayShortName.ifBlank { live.awayAbbr }, live.awayScore, compact)
            Spacer(GlanceModifier.height(3.dp))
            ScoreLine(live.homeShortName.ifBlank { live.homeAbbr }, live.homeScore, compact)
            Spacer(GlanceModifier.height(if (compact) 8.dp else 6.dp))
            Text(
                text = live.statusDetail,
                style = TextStyle(
                    color = ColorProvider(if (isLive) liveOrange else muted),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
        }
    }

    @Composable
    private fun ScoreLine(name: String, score: Int, compact: Boolean) {
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = name,
                style = TextStyle(
                    color = ColorProvider(Color.White),
                    fontSize = if (compact) 15.sp else 14.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
                modifier = GlanceModifier.defaultWeight(),
            )
            Text(
                text = "$score",
                style = TextStyle(
                    color = ColorProvider(Color.White),
                    fontSize = if (compact) 22.sp else 20.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
        }
    }

    private fun kindLabel(kind: String): String = when (kind) {
        "live" -> "live now"
        "new" -> "new for you"
        "soon" -> "dropping soon"
        "out" -> "out now"
        else -> "next up"
    }

    @Composable
    private fun SmallWidget(payload: WidgetPayload) {
        val items = payload.items
        val leadKind = items.firstOrNull()?.kind ?: "soon"
        val leadColor = kindColor(leadKind)

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .padding(12.dp),
        ) {
            // Brand wordmark
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "Guide",
                    style = TextStyle(
                        color = ColorProvider(Color.White),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Text(
                    text = "Stream",
                    style = TextStyle(
                        color = ColorProvider(Color(red = 0xF5, green = 0x82, blue = 0x1F)),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Text(
                    text = "TV",
                    style = TextStyle(
                        color = ColorProvider(Color(red = 0x5B, green = 0xB0, blue = 0xFF)),
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
            }

            Spacer(GlanceModifier.height(10.dp))

            // Total item count
            Text(
                text = "${items.size}",
                style = TextStyle(
                    color = ColorProvider(leadColor),
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
            Text(
                text = kindLabel(leadKind),
                style = TextStyle(
                    color = ColorProvider(Color.White.copy(alpha = 0.5f)),
                    fontSize = 10.sp,
                ),
            )

            Spacer(GlanceModifier.height(6.dp))

            // Live indicator
            if (payload.liveCount > 0) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "●",
                        style = TextStyle(
                            color = ColorProvider(kindColor("live")),
                            fontSize = 8.sp,
                        ),
                    )
                    Spacer(GlanceModifier.width(4.dp))
                    Text(
                        text = "${payload.liveCount} live now",
                        style = TextStyle(
                            color = ColorProvider(kindColor("live")),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                    )
                }
            }
        }
    }

    @Composable
    private fun MediumWidget(payload: WidgetPayload, context: Context) {
        val items = payload.items
        val leadKind = items.firstOrNull()?.kind ?: "soon"
        val eyebrowColor = if (leadKind == "live") kindColor("live") else Color(red = 0xF5, green = 0x82, blue = 0x1F)

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .padding(14.dp),
        ) {
            // Header — wordmark + NEXT UP eyebrow
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Guide",
                    style = TextStyle(
                        color = ColorProvider(Color.White),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Text(
                    text = "Stream",
                    style = TextStyle(
                        color = ColorProvider(Color(red = 0xF5, green = 0x82, blue = 0x1F)),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Text(
                    text = "TV",
                    style = TextStyle(
                        color = ColorProvider(Color(red = 0x5B, green = 0xB0, blue = 0xFF)),
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Spacer(GlanceModifier.width(6.dp))
                if (leadKind == "live") {
                    Text(
                        text = "●",
                        style = TextStyle(
                            color = ColorProvider(kindColor("live")),
                            fontSize = 8.sp,
                        ),
                    )
                    Spacer(GlanceModifier.width(3.dp))
                }
                Text(
                    text = "NEXT UP",
                    style = TextStyle(
                        color = ColorProvider(eyebrowColor),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                if (items.isNotEmpty()) {
                    Text(
                        text = " · ${items.size}",
                        style = TextStyle(
                            color = ColorProvider(Color.White.copy(alpha = 0.4f)),
                            fontSize = 10.sp,
                        ),
                    )
                }
            }

            Spacer(GlanceModifier.height(8.dp))

            // Rows — first 3 items
            if (items.isNotEmpty()) {
                items.take(3).forEach { item ->
                    FeedRow(item, context)
                    Spacer(GlanceModifier.height(4.dp))
                }
            } else {
                Text(
                    text = "Nothing dropping right now",
                    style = TextStyle(
                        color = ColorProvider(Color.White.copy(alpha = 0.4f)),
                        fontSize = 13.sp,
                    ),
                )
                Spacer(GlanceModifier.height(2.dp))
                Text(
                    text = "Follow a show to fill this in",
                    style = TextStyle(
                        color = ColorProvider(Color.White.copy(alpha = 0.25f)),
                        fontSize = 10.sp,
                    ),
                )
            }

            Spacer(GlanceModifier.height(6.dp))

            // Stats bar
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                horizontalAlignment = Alignment.End,
            ) {
                Text(
                    text = "📺 ${payload.watchlistCount}  ✨ ${payload.newEpisodeCount}",
                    style = TextStyle(
                        color = ColorProvider(Color.White.copy(alpha = 0.5f)),
                        fontSize = 10.sp,
                    ),
                )
            }

            // Timestamp (only if within 24h)
            val now = System.currentTimeMillis()
            if (payload.lastUpdated > 0 && now - payload.lastUpdated < 24 * 60 * 60 * 1000L) {
                val minutesAgo = (now - payload.lastUpdated) / 60000
                val agoText = if (minutesAgo < 60) "${minutesAgo}m ago" else "${minutesAgo / 60}h ago"
                Text(
                    text = agoText,
                    style = TextStyle(
                        color = ColorProvider(Color.White.copy(alpha = 0.3f)),
                        fontSize = 9.sp,
                    ),
                )
            }
        }
    }

    @Composable
    private fun LargeWidget(payload: WidgetPayload, context: Context) {
        val items = payload.items
        val leadKind = items.firstOrNull()?.kind ?: "soon"
        val eyebrowColor = if (leadKind == "live") kindColor("live") else Color(red = 0xF5, green = 0x82, blue = 0x1F)

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .padding(14.dp),
        ) {
            // Header
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Guide",
                    style = TextStyle(
                        color = ColorProvider(Color.White),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Text(
                    text = "Stream",
                    style = TextStyle(
                        color = ColorProvider(Color(red = 0xF5, green = 0x82, blue = 0x1F)),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Text(
                    text = "TV",
                    style = TextStyle(
                        color = ColorProvider(Color(red = 0x5B, green = 0xB0, blue = 0xFF)),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Spacer(GlanceModifier.width(8.dp))
                if (leadKind == "live") {
                    Text(
                        text = "●",
                        style = TextStyle(
                            color = ColorProvider(kindColor("live")),
                            fontSize = 8.sp,
                        ),
                    )
                    Spacer(GlanceModifier.width(3.dp))
                }
                Text(
                    text = "NEXT UP",
                    style = TextStyle(
                        color = ColorProvider(eyebrowColor),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                if (items.isNotEmpty()) {
                    Text(
                        text = " · ${items.size}",
                        style = TextStyle(
                            color = ColorProvider(Color.White.copy(alpha = 0.4f)),
                            fontSize = 12.sp,
                        ),
                    )
                }
            }

            Spacer(GlanceModifier.height(6.dp))

            // Stats row
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                horizontalAlignment = Alignment.Start,
            ) {
                Text(
                    text = "📺 ${payload.watchlistCount}  ✨ ${payload.newEpisodeCount}  🔴 ${payload.liveCount}",
                    style = TextStyle(
                        color = ColorProvider(Color.White.copy(alpha = 0.5f)),
                        fontSize = 10.sp,
                    ),
                )
            }

            Spacer(GlanceModifier.height(8.dp))

            // Rows — first 7 items
            if (items.isNotEmpty()) {
                items.take(7).forEach { item ->
                    FeedRow(item, context)
                    Spacer(GlanceModifier.height(5.dp))
                }
            } else {
                Text(
                    text = "Nothing dropping right now",
                    style = TextStyle(
                        color = ColorProvider(Color.White.copy(alpha = 0.4f)),
                        fontSize = 14.sp,
                    ),
                    modifier = GlanceModifier.padding(vertical = 16.dp),
                )
                Text(
                    text = "Follow a show to fill this in",
                    style = TextStyle(
                        color = ColorProvider(Color.White.copy(alpha = 0.25f)),
                        fontSize = 11.sp,
                    ),
                )
            }
        }
    }

    /**
     * One feed row: 3pt wide rounded platform colour bar, title (12.5pt
     * semibold white, one line, truncated), spacer, badge (9.5pt bold in its
     * kind colour). Wrapped in a .clickable that opens the deep link via an
     * ACTION_VIEW intent when the item has a non-null deepLink.
     */
    @Composable
    private fun FeedRow(item: WidgetFeedItem, context: Context) {
        val badgeColor = kindColor(item.kind)
        val platformColor = parseHexColor(item.platformColorHex)

        val rowModifier = if (!item.deepLink.isNullOrEmpty()) {
            GlanceModifier.fillMaxWidth().wrapContentHeight().clickable {
                context.startActivity(
                    Intent(Intent.ACTION_VIEW, Uri.parse(item.deepLink))
                        .setClass(context, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            }
        } else {
            GlanceModifier.fillMaxWidth().wrapContentHeight()
        }

        Row(
            modifier = rowModifier,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Platform colour bar — 3dp wide
            Box(
                modifier = GlanceModifier
                    .width(3.dp)
                    .height(18.dp)
                    .background(platformColor),
            ) {}
            Spacer(GlanceModifier.width(8.dp))
            // Title — 12.5sp semibold white, one line, truncated
            Text(
                text = item.title,
                style = TextStyle(
                    color = ColorProvider(Color.White),
                    fontSize = 12.5.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
                modifier = GlanceModifier.padding(end = 4.dp).defaultWeight(),
            )
            Spacer(GlanceModifier.width(4.dp))
            // Badge — 9.5sp bold in kind colour
            Text(
                text = item.badge,
                style = TextStyle(
                    color = ColorProvider(badgeColor),
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
        }
    }

    private fun parseHexColor(hex: String): Color {
        return try {
            val clean = hex.removePrefix("#")
            val value = if (clean.length == 8) {
                clean.toLong(16)
            } else if (clean.length == 6) {
                (0xFF000000L or clean.toLong(16))
            } else {
                0xFFF5821FL
            }
            Color(value.toInt())
        } catch (_: Exception) {
            Color(0xFFF5821F)
        }
    }
}

/**
 * Widget receiver — registers the widget with the system.
 */
class GuideStreamWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = GuideStreamWidget()
}
