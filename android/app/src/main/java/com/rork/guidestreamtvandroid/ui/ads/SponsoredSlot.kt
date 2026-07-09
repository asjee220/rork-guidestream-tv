package com.rork.guidestreamtvandroid.ui.ads

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.StreamingService
import com.rork.guidestreamtvandroid.data.repository.RakutenManager
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Preferred ad source for a pooled inline slot — mirrors iOS PooledAdSource.
 * ADMOB_FIRST shows a native AdMob unit when it fills and backfills with the
 * Rakuten affiliate presentation; RAKUTEN_FIRST renders Rakuten directly.
 */
enum class PooledAdSource {
    ADMOB_FIRST,
    RAKUTEN_FIRST,
}

/**
 * Pooled inline sponsored slot inserted between home feed rows — mirrors iOS
 * SponsoredSlotView. Renders a compact glass card with a "Sponsored" label and
 * a dismiss control. ADMOB_FIRST attempts a native AdMob unit and swaps to the
 * Rakuten affiliate presentation if it fails to fill; RAKUTEN_FIRST renders the
 * Rakuten presentation directly, so a slot is never blank.
 */
@Composable
fun SponsoredSlot(
    preferredSource: PooledAdSource,
    service: StreamingService?,
    serviceId: String,
    headline: String,
    subtitle: String,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    // Log a single ad impression when this slot first composes.
    LaunchedEffect(serviceId) {
        WatchIntentLogger.get().log(
            WatchIntentLogger.IntentEventType.AD_IMPRESSION,
            metadata = mapOf("ad_type" to "home_inline", "source" to "home_inline"),
        )
    }

    // For ADMOB_FIRST, track whether the AdMob unit failed so we can backfill.
    var adMobFailed by remember(serviceId) { mutableStateOf(false) }
    val showRakuten = preferredSource == PooledAdSource.RAKUTEN_FIRST || adMobFailed

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(GlassFill)
            .border(1.dp, GlassStroke, RoundedCornerShape(14.dp))
            .padding(12.dp),
    ) {
        // Header — "Sponsored" label + dismiss x
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(4.dp))
                    .background(BrandOrange.copy(alpha = 0.2f))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            ) {
                Text(
                    text = "Sponsored",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = BrandOrange,
                )
            }
            Spacer(Modifier.weight(1f))
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = "Dismiss ad",
                tint = TextTertiary,
                modifier = Modifier
                    .size(20.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onDismiss() },
            )
        }
        Spacer(Modifier.height(8.dp))

        if (showRakuten) {
            RakutenAffiliatePresentation(
                service = service,
                headline = headline,
                subtitle = subtitle,
                onClick = {
                    RakutenManager.get().openAffiliateLink(
                        serviceId = serviceId,
                        context = context,
                        metadata = mapOf("section" to "home_inline_ad"),
                    )
                },
            )
        } else {
            NativeAdCard(
                onAdFailedToLoad = { adMobFailed = true },
            )
        }
    }
}

/**
 * Inline Rakuten affiliate presentation — a branded tile, headline, subtitle,
 * and a "Get offer" call to action. Tapping anywhere opens the tracked link.
 */
@Composable
private fun RakutenAffiliatePresentation(
    service: StreamingService?,
    headline: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Brand tile
        Box(
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(service?.bg ?: Color.White.copy(alpha = 0.10f))
                .border(0.5.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(8.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = (service?.name ?: headline).take(3).uppercase(),
                fontSize = 14.sp,
                fontWeight = FontWeight.Black,
                color = service?.glow ?: Color.White,
            )
        }
        Spacer(Modifier.width(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = headline,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (subtitle.isNotEmpty()) {
                Text(
                    text = subtitle,
                    fontSize = 10.sp,
                    color = TextSecondary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text(
                text = "Sponsored · Rakuten",
                fontSize = 9.sp,
                color = TextTertiary,
            )
        }
        Spacer(Modifier.width(8.dp))
        Box(
            modifier = Modifier
                .heightIn(min = 28.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(BrandOrange)
                .padding(horizontal = 12.dp, vertical = 6.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "Get offer",
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
        }
    }
}
