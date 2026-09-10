package com.rork.guidestreamtvandroid.ui.ads

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary

/**
 * Last-resort fill for a sponsored slot: a house card promoting the app's own
 * features. Mirrors iOS HouseSlotCard.swift.
 *
 * WHY THIS EXISTS. A slot picks an affiliate offer from a pool of eight
 * services, filtered to the ones the viewer does NOT already subscribe to —
 * the app must never advertise something they already pay for. A viewer who
 * subscribes to all eight therefore had no eligible offer anywhere, and
 * `if (!allowRakutenFallback && adMobFailed) return` rendered nothing at all,
 * so the most engaged users saw empty slots across the whole app.
 *
 * This keeps the promise without the dead space. It is the LAST resort: an
 * eligible affiliate offer wins, and a native ad still takes the slot when one
 * fills.
 */
data class HouseOffer(
    val icon: ImageVector,
    val headline: String,
    val subtitle: String,
)

private val HOUSE_POOL = listOf(
    HouseOffer(Icons.Filled.PlayArrow, "One watchlist, every service",
        "Save a show once and see it wherever you watch"),
    HouseOffer(Icons.Filled.Notifications, "Never miss a premiere",
        "Get told the day a new episode lands"),
    HouseOffer(Icons.Filled.Star, "Follow your teams",
        "Live scores and where the game is on"),
    HouseOffer(Icons.Filled.Tv, "Watch on the big screen",
        "GuideStream TV is on Android TV too"),
)

fun houseOfferFor(seed: String): HouseOffer =
    HOUSE_POOL[(kotlin.math.abs(seed.hashCode())) % HOUSE_POOL.size]

@Composable
fun HouseSlotCard(
    offer: HouseOffer,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    feedStyle: Boolean = true,
) {
    val cardHeight = if (feedStyle) 96.dp else 84.dp
    val plate = if (feedStyle) 56.dp else 44.dp

    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(cardHeight)
            .clip(RoundedCornerShape(14.dp))
            .background(Color.White.copy(alpha = 0.06f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(plate)
                .clip(RoundedCornerShape(10.dp))
                .background(BrandOrange.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = offer.icon,
                contentDescription = null,
                tint = BrandOrange,
                modifier = Modifier.size(plate * 0.46f),
            )
        }

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = offer.headline,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = offer.subtitle,
                fontSize = 12.sp,
                color = TextSecondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Box(
            modifier = Modifier
                .size(28.dp)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onDismiss() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = "Dismiss",
                tint = Color.White.copy(alpha = 0.35f),
                modifier = Modifier.size(14.dp),
            )
        }
    }
}
