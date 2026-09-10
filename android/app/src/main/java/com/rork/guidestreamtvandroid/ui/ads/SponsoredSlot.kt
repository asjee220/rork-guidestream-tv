package com.rork.guidestreamtvandroid.ui.ads

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
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
import com.rork.guidestreamtvandroid.ui.components.ServiceBrandContent
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.SurfaceContainer
import com.rork.guidestreamtvandroid.ui.theme.SurfaceElevated
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
 * SponsoredSlotView. In feed style it renders the 96dp inline chip — 72dp
 * creative square, up to three lines of headline, an "advertiser · Sponsored"
 * line, and a top-end close control; otherwise a compact glass card with a
 * "Sponsored" label.
 * ADMOB_FIRST attempts a native AdMob unit and swaps to the
 * Rakuten affiliate presentation if it fails to fill; RAKUTEN_FIRST renders the
 * Rakuten presentation directly, so a slot is never blank. When
 * [allowRakutenFallback] is false the Rakuten presentation is never rendered,
 * the native AdMob path is attempted regardless of [preferredSource], and a
 * failed native fill renders nothing at all — no card, no header, no
 * impression log — so an unfillable slot occupies no space.
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
    adSource: String = "home_inline",
    sectionKey: String = "home_inline_ad",
    allowRakutenFallback: Boolean = true,
    feedStyle: Boolean = true,
) {
    val context = LocalContext.current

    // For ADMOB_FIRST, track whether the AdMob unit failed so we can backfill.
    var adMobFailed by remember(serviceId) { mutableStateOf(false) }
    var adMobLoaded by remember(serviceId) { mutableStateOf(false) }

    // Hard off-switch: when the Rakuten fallback is disallowed, always
    // attempt the native AdMob path regardless of preferredSource and never
    // render the Rakuten affiliate presentation.
    val showRakuten = allowRakutenFallback &&
        (preferredSource == PooledAdSource.RAKUTEN_FIRST || adMobFailed)

    // No eligible Rakuten offer and the native unit failed to fill — render
    // nothing at all: no card container, no Sponsored header, no impression.
    if (!allowRakutenFallback && adMobFailed) return

    // Log a single ad impression once the slot actually renders something.
    // Fallback-free slots log only after the native ad has loaded, so a
    // no-fill slot logs nothing at all.
    val shouldLogImpression = allowRakutenFallback || adMobLoaded
    LaunchedEffect(serviceId, shouldLogImpression) {
        if (shouldLogImpression) {
            WatchIntentLogger.get().log(
                WatchIntentLogger.IntentEventType.AD_IMPRESSION,
                metadata = mapOf("ad_type" to adSource, "source" to adSource),
            )
        }
    }

    val openOffer = {
        RakutenManager.get().openAffiliateLink(
            serviceId = serviceId,
            context = context,
            metadata = mapOf("section" to sectionKey),
        )
    }

    if (feedStyle) {
        // Feed chip — the surface lives here so the affiliate and banner
        // presentations sit in an identically sized box and a late banner
        // fill causes no layout shift.
        Box(
            modifier = modifier
                .fillMaxWidth()
                .height(96.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(SurfaceElevated)
                .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp)),
        ) {
            if (showRakuten) {
                RakutenAffiliatePresentation(
                    service = service,
                    headline = headline,
                    subtitle = subtitle,
                    feedStyle = true,
                    onClick = openOffer,
                )
            } else {
                NativeAdCard(
                    feedStyle = true,
                    onAdLoaded = { adMobLoaded = true },
                    onAdFailedToLoad = { adMobFailed = true },
                )
            }

            // Close — drawn above the card so its tap never opens the offer.
            Box(
                modifier = Modifier
                    // 44dp target for the Material minimum; the glyph still
                    // reads as a small X because the box is transparent.
                    .align(Alignment.TopEnd)
                    .size(44.dp)
                    .clip(CircleShape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onDismiss() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.Close,
                    contentDescription = "Hide this ad",
                    tint = Color.White.copy(alpha = 0.55f),
                    modifier = Modifier.size(15.dp),
                )
            }
        }
        return
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(GlassFill)
            .border(1.dp, GlassStroke, RoundedCornerShape(14.dp))
            .padding(12.dp),
    ) {
        // Header — "Sponsored" label
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
        Spacer(Modifier.height(8.dp))

        if (showRakuten) {
            RakutenAffiliatePresentation(
                service = service,
                headline = headline,
                subtitle = subtitle,
                feedStyle = false,
                onClick = openOffer,
            )
        } else {
            NativeAdCard(
                feedStyle = false,
                onAdLoaded = { adMobLoaded = true },
                onAdFailedToLoad = { adMobFailed = true },
            )
        }
    }
}

/**
 * Inline Rakuten affiliate presentation. In feed style it is the 96dp chip:
 * a flush 96dp brand square, up to three lines of headline, and an
 * "advertiser · Sponsored" line. Otherwise the older tile + subtitle +
 * "Get offer" row. Tapping anywhere opens the tracked link.
 */
@Composable
internal fun RakutenAffiliatePresentation(
    service: StreamingService?,
    headline: String,
    subtitle: String,
    feedStyle: Boolean,
    onClick: () -> Unit,
) {
    if (feedStyle) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onClick() },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Creative — flush to the start edge and the full height of the
            // chip. Square-cornered: the caller's clip rounds the two corners
            // that meet the card's edges.
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .width(96.dp)
                    .background(service?.bg ?: SurfaceContainer),
                contentAlignment = Alignment.Center,
            ) {
                if (service != null) {
                    // Draw the brand's own wordmark, as iOS does. Several
                    // brands set `glow` equal to `bg` (hulu, paramount,
                    // disney, hbo), so initials tinted with `glow` render as
                    // an empty colour block.
                    ServiceBrandContent(
                        display = service.display,
                        diameter = 96.dp,
                        modifier = Modifier.padding(horizontal = 10.dp),
                    )
                } else {
                    Text(
                        text = headline.take(3).uppercase(),
                        fontSize = 19.sp,
                        fontWeight = FontWeight.Black,
                        color = Color.White,
                    )
                }
            }
            Spacer(Modifier.width(12.dp))
            Column(
                modifier = Modifier
                    .weight(1f)
                    // End inset clears the close control so a three-line
                    // headline never runs underneath it.
                    .padding(end = 44.dp, top = 12.dp, bottom = 12.dp),
            ) {
                Text(
                    text = headline,
                    fontSize = 14.sp,
                    lineHeight = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextPrimary,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(5.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = service?.name ?: headline,
                        fontSize = 11.sp,
                        lineHeight = 14.sp,
                        color = Color.White.copy(alpha = 0.52f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.width(5.dp))
                    // Required attribution, right after the advertiser name.
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(3.dp))
                            .background(Color.White.copy(alpha = 0.12f))
                            .padding(horizontal = 5.dp, vertical = 1.dp),
                    ) {
                        Text(
                            text = "Sponsored",
                            fontSize = 10.sp,
                            lineHeight = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White.copy(alpha = 0.62f),
                        )
                    }
                }
            }
        }
        return
    }

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
                .background(service?.bg ?: SurfaceContainer)
                .border(0.5.dp, OutlineVariant, RoundedCornerShape(8.dp)),
            contentAlignment = Alignment.Center,
        ) {
            if (service != null) {
                ServiceBrandContent(
                    display = service.display,
                    diameter = 56.dp,
                    modifier = Modifier.padding(horizontal = 6.dp),
                )
            } else {
                Text(
                    text = headline.take(3).uppercase(),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Black,
                    color = Color.White,
                )
            }
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
