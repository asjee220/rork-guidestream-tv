package com.rork.guidestreamtvandroid.widget

import android.content.Context
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

/**
 * Guide Stream TV home-screen widget — mirrors iOS GuideStreamWidget.swift.
 * Renders Leaving Soon rows (or NEW EPISODES fallback when empty),
 * brand wordmark, stats bar, and timestamp (hidden when >24h).
 * Refresh policy: 30 minutes.
 */
class GuideStreamWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val prefs = context.getSharedPreferences("gs_widget_payload", Context.MODE_PRIVATE)
        val service = WidgetDataService.get()
        val payload = service.loadPayload()

        provideContent {
            GlanceTheme {
                WidgetContent(payload)
            }
        }
    }

    @Composable
    private fun WidgetContent(payload: WidgetPayload) {
        val size = LocalSize.current
        val isSmall = size.width < 200.dp
        val isMedium = size.width >= 200.dp && size.width < 300.dp

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(Color(red = 0x04, green = 0x09, blue = 0x0F))
                .clickable(actionStartActivity<MainActivity>()),
        ) {
            if (isSmall) {
                SmallWidget(payload)
            } else if (isMedium) {
                MediumWidget(payload)
            } else {
                LargeWidget(payload)
            }
        }
    }

    @Composable
    private fun SmallWidget(payload: WidgetPayload) {
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = "GuideStream",
                style = TextStyle(
                    color = ColorProvider(Color.White),
                    fontSize = 14.sp,
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
            Spacer(GlanceModifier.height(8.dp))
            Text(
                text = "${payload.watchlistCount}",
                style = TextStyle(
                    color = ColorProvider(Color(red = 0xF5, green = 0x82, blue = 0x1F)),
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
            Text(
                text = "Watching",
                style = TextStyle(
                    color = ColorProvider(Color.White.copy(alpha = 0.55f)),
                    fontSize = 10.sp,
                ),
            )
        }
    }

    @Composable
    private fun MediumWidget(payload: WidgetPayload) {
        val hasLeavingSoon = payload.leavingSoon.isNotEmpty()
        val hasNewEpisodes = !payload.newEpisodes.isNullOrEmpty()
        val showNewEpisodes = !hasLeavingSoon && hasNewEpisodes

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
                Text(
                    text = if (showNewEpisodes) "NEW EPISODES" else "LEAVING SOON",
                    style = TextStyle(
                        color = ColorProvider(if (showNewEpisodes) Color(red = 0x00, green = 0x9E, blue = 0x8A) else Color(red = 0xF5, green = 0x82, blue = 0x1F)),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                val count = if (showNewEpisodes) payload.newEpisodes!!.size else payload.leavingSoon.size
                Text(
                    text = " · $count ${if (showNewEpisodes) "new" else "left"}",
                    style = TextStyle(
                        color = ColorProvider(Color.White.copy(alpha = 0.4f)),
                        fontSize = 11.sp,
                    ),
                )
            }

            Spacer(GlanceModifier.height(8.dp))

            // Rows
            if (showNewEpisodes) {
                payload.newEpisodes!!.take(3).forEach { item ->
                    WidgetRow(
                        title = item.title,
                        badgeText = item.episodeLabel,
                        badgeColor = Color(red = 0x00, green = 0x9E, blue = 0x8A),
                        platformColor = parseHexColor(item.platformColorHex),
                    )
                    Spacer(GlanceModifier.height(4.dp))
                }
            } else if (hasLeavingSoon) {
                payload.leavingSoon.take(3).forEach { item ->
                    WidgetRow(
                        title = item.title,
                        badgeText = if (item.daysLeft == 0) "Today" else "${item.daysLeft}d left",
                        badgeColor = Color(red = 0xF5, green = 0x82, blue = 0x1F),
                        platformColor = parseHexColor(item.platformColorHex),
                    )
                    Spacer(GlanceModifier.height(4.dp))
                }
            } else {
                Text(
                    text = "No titles leaving soon",
                    style = TextStyle(
                        color = ColorProvider(Color.White.copy(alpha = 0.35f)),
                        fontSize = 12.sp,
                    ),
                    modifier = GlanceModifier.padding(vertical = 16.dp),
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
    private fun LargeWidget(payload: WidgetPayload) {
        val hasLeavingSoon = payload.leavingSoon.isNotEmpty()
        val hasNewEpisodes = !payload.newEpisodes.isNullOrEmpty()
        val showNewEpisodes = !hasLeavingSoon && hasNewEpisodes

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
                    text = "GuideStream TV",
                    style = TextStyle(
                        color = ColorProvider(Color.White),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Spacer(GlanceModifier.width(8.dp))
                Text(
                    text = if (showNewEpisodes) "NEW EPISODES" else "LEAVING SOON",
                    style = TextStyle(
                        color = ColorProvider(if (showNewEpisodes) Color(red = 0x00, green = 0x9E, blue = 0x8A) else Color(red = 0xF5, green = 0x82, blue = 0x1F)),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
            }

            Spacer(GlanceModifier.height(8.dp))

            // Rows — up to 8 for large
            if (showNewEpisodes) {
                payload.newEpisodes!!.take(8).forEach { item ->
                    WidgetRow(
                        title = item.title,
                        badgeText = item.episodeLabel,
                        badgeColor = Color(red = 0x00, green = 0x9E, blue = 0x8A),
                        platformColor = parseHexColor(item.platformColorHex),
                    )
                    Spacer(GlanceModifier.height(4.dp))
                }
            } else if (hasLeavingSoon) {
                payload.leavingSoon.take(8).forEach { item ->
                    WidgetRow(
                        title = item.title,
                        badgeText = if (item.daysLeft == 0) "Today" else "${item.daysLeft}d left",
                        badgeColor = Color(red = 0xF5, green = 0x82, blue = 0x1F),
                        platformColor = parseHexColor(item.platformColorHex),
                    )
                    Spacer(GlanceModifier.height(4.dp))
                }
            } else {
                Text(
                    text = "No titles leaving soon",
                    style = TextStyle(
                        color = ColorProvider(Color.White.copy(alpha = 0.35f)),
                        fontSize = 13.sp,
                    ),
                    modifier = GlanceModifier.padding(vertical = 16.dp),
                )
            }
        }
    }

    @Composable
    private fun WidgetRow(
        title: String,
        badgeText: String,
        badgeColor: Color,
        platformColor: Color,
    ) {
        Row(
            modifier = GlanceModifier.fillMaxWidth().wrapContentHeight(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Platform pill
            Box(
                modifier = GlanceModifier
                    .width(4.dp)
                    .height(24.dp)
                    .background(platformColor),
            ) {}
            Spacer(GlanceModifier.width(8.dp))
            Text(
                text = title,
                style = TextStyle(
                    color = ColorProvider(Color.White),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                ),
                modifier = GlanceModifier.padding(end = 4.dp),
            )
            Spacer(GlanceModifier.width(4.dp))
            Text(
                text = badgeText,
                style = TextStyle(
                    color = ColorProvider(badgeColor),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                ),
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
