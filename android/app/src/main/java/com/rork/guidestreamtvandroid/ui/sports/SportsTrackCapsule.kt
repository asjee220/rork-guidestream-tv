package com.rork.guidestreamtvandroid.ui.sports

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.material3.Text
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.repository.SportsLiveScoreController
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.LightBlue
import kotlinx.coroutines.launch

/**
 * Live-score tracking capsule — the Android counterpart of iOS's
 * SportsTrackCapsule, down to the three states and the same copy. Shared by the
 * watch sheet and the game detail screen so the two cannot drift.
 *
 * The wording differs from iOS in exactly one place: the hint says "notification"
 * rather than "Dynamic Island", because that is what Android actually shows.
 */
object SportsTrackAvailability {
    /**
     * Whether the capsule should appear at all: notifications allowed AND the
     * game is live or starts within the hour. Mirrors iOS
     * SportsTrackCapsule.isAvailable(for:).
     */
    fun isAvailable(context: android.content.Context, game: SportsGame): Boolean {
        if (!SportsLiveScoreController.init(context).isAvailable()) return false
        return when (game.state) {
            "live" -> true
            "pre" -> {
                val start = game.startDate ?: return false
                start - System.currentTimeMillis() <= 60 * 60 * 1000L
            }
            else -> false
        }
    }
}

@Composable
fun SportsTrackCapsule(
    game: SportsGame,
    broadcast: String,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val controller = remember { SportsLiveScoreController.init(context) }
    if (!SportsTrackAvailability.isAvailable(context, game)) return

    val scope = rememberCoroutineScope()
    val trackedGameId by controller.trackedGameId.collectAsStateWithLifecycle()
    val lastError by controller.lastStartError.collectAsStateWithLifecycle()

    val isTrackingThis = trackedGameId == game.id
    val isTrackingOther = trackedGameId != null && trackedGameId != game.id

    val accent = when {
        isTrackingThis -> BrandOrange
        isTrackingOther -> LightBlue
        else -> Color.White
    }
    val fill = when {
        isTrackingThis -> BrandOrange.copy(alpha = 0.16f)
        isTrackingOther -> LightBlue.copy(alpha = 0.16f)
        else -> Color.White.copy(alpha = 0.08f)
    }
    val border = when {
        isTrackingThis -> BrandOrange
        isTrackingOther -> LightBlue
        else -> Color.White.copy(alpha = 0.13f)
    }
    val title = when {
        isTrackingThis -> "Tracking · Stop"
        isTrackingOther -> "Switch to this game"
        else -> "Track live score"
    }
    val hint = when {
        isTrackingThis -> "Showing in your notifications. Ends automatically at final."
        isTrackingOther -> "Switching ends the game you're currently tracking."
        else -> "Live score in your notifications until the final whistle."
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .clip(CircleShape)
                .background(fill)
                .border(1.dp, border, CircleShape)
                .clickable {
                    scope.launch {
                        if (isTrackingThis) controller.stop()
                        else controller.start(game, broadcast)
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (isTrackingThis) {
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .clip(CircleShape)
                            .background(BrandOrange),
                    )
                }
                Text(
                    text = title,
                    color = accent,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }

        Text(
            text = hint,
            color = Color.White.copy(alpha = 0.45f),
            fontSize = 11.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )

        lastError?.let { message ->
            Text(
                text = message,
                color = Color(red = 0xFF, green = 0x3B, blue = 0x30),
                fontSize = 11.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp)
                    .clickable { controller.clearLastError() },
            )
        }
    }
}
