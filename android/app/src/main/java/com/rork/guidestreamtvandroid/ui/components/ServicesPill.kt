package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.StreamingService
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Navy

/**
 * Orange-outlined pill that sits to the right of the GuideStream TV wordmark
 * in the top bar on Home. Shows the user's first three selected services as
 * overlapping mini-icons with a small counter badge. Tapping opens the
 * services editor sheet. Mirrors iOS ServicesPill.swift.
 *
 * GUI-101: with nothing selected the pill keeps its silhouette and position
 * and shows three dashed placeholder rings plus the word "Add" — rather than
 * an empty capsule with a "0" badge, which read as a broken control to anyone
 * who skipped the services step during onboarding.
 */
@Composable
fun ServicesPill(
    serviceIds: List<String>,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val topServices = serviceIds.mapNotNull { StreamingCatalog.service(it) }.take(3)
    val iconDiameter = 22.dp
    val stride = 13.dp
    val isEmpty = serviceIds.isEmpty()

    Box(modifier = modifier) {
        Row(
            modifier = Modifier
                .shadow(elevation = 8.dp, shape = CircleShape, ambientColor = BrandOrange.copy(alpha = 0.25f), spotColor = BrandOrange.copy(alpha = 0.25f))
                .clip(CircleShape)
                .background(BrandOrange.copy(alpha = 0.10f))
                .border(1.4.dp, BrandOrange, CircleShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onTap() }
                .padding(start = 6.dp, end = 10.dp, top = 5.dp, bottom = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Overlapping stacked mini-icons, or three dashed rings holding
            // exactly that space when nothing is selected.
            val ghostCount = 3
            val stackWidth =
                if (isEmpty) stride * (ghostCount - 1) + iconDiameter
                else stride * (maxOf(topServices.size, 1) - 1) + iconDiameter
            Box(
                modifier = Modifier.width(stackWidth),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (isEmpty) {
                    repeat(ghostCount) { index ->
                        GhostServiceRing(
                            size = iconDiameter,
                            modifier = Modifier.offset(x = stride * index),
                        )
                    }
                } else {
                    topServices.forEachIndexed { index, service ->
                        ServiceMiniIcon(
                            service = service,
                            size = iconDiameter,
                            modifier = Modifier.offset(x = stride * index),
                        )
                    }
                }
            }
            if (isEmpty) {
                Text(
                    text = "Add",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Black,
                    color = BrandOrange,
                )
            }
            Icon(
                imageVector = Icons.Filled.KeyboardArrowDown,
                contentDescription = null,
                tint = BrandOrange.copy(alpha = 0.75f),
                modifier = Modifier.size(14.dp),
            )
        }

        // Counter badge, top-right. Suppressed in the empty state — a "0"
        // reads as a broken counter, and the dashed rings already say
        // "nothing here".
        if (!isEmpty) {
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .offset(x = 6.dp, y = (-7).dp)
                .clip(CircleShape)
                .background(BrandOrange)
                .border(1.5.dp, Navy, CircleShape)
                .padding(horizontal = 5.dp, vertical = 1.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = serviceIds.size.toString(),
                fontSize = 9.sp,
                fontWeight = FontWeight.Black,
                color = Color.White,
            )
        }
        }
    }
}

/**
 * Dashed placeholder ring standing in for a service icon that has not been
 * chosen yet. Filled with the bar's own navy so the rings occlude each other
 * the way the real stack does, where each icon carries a navy border.
 */
@Composable
private fun GhostServiceRing(
    size: androidx.compose.ui.unit.Dp,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(Navy)
            .drawBehind {
                drawCircle(
                    color = BrandOrange.copy(alpha = 0.55f),
                    radius = this.size.minDimension / 2f - 0.6.dp.toPx(),
                    style = Stroke(
                        width = 1.2.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(
                            floatArrayOf(3.dp.toPx(), 2.5.dp.toPx()),
                            0f,
                        ),
                    ),
                )
            },
    )
}

@Composable
private fun ServiceMiniIcon(
    service: StreamingService,
    size: androidx.compose.ui.unit.Dp,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(service.bg)
            .border(1.5.dp, Navy, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        ServiceBrandContent(
            display = service.display,
            diameter = size,
            modifier = Modifier.padding(size * 0.14f),
        )
    }
}

/**
 * Renders the brand-specific content for a streaming service — the wordmark,
 * symbol or star it is actually known by. Mirrors iOS `ServiceBrandContent`
 * in `StreamingServiceViews.swift`. Shared beyond the circular mini-icon:
 * the inline ad chip draws it too, because several brands (hulu, paramount,
 * disney, hbo) carry a `glow` that equals their `bg`, so a tile drawn in
 * `glow` on `bg` renders as a solid colour block with nothing legible on it.
 */
@Composable
internal fun ServiceBrandContent(
    display: StreamingService.Display,
    diameter: androidx.compose.ui.unit.Dp,
    modifier: Modifier = Modifier,
) {
    when (display) {
        is StreamingService.Display.Text -> {
            val text = display.text
            val fontSize = when {
                text.length <= 1 -> diameter * 0.55f
                text.contains("\n") -> diameter * 0.30f
                text.length <= 3 -> diameter * 0.55f
                text.length <= 5 -> diameter * 0.36f
                else -> diameter * 0.28f
            }
            Text(
                text = text,
                fontSize = fontSize.value.sp,
                fontWeight = display.weight,
                color = display.color,
                textAlign = TextAlign.Center,
                lineHeight = if (text.contains("\n")) fontSize.value.sp * 0.85f else fontSize.value.sp,
                maxLines = if (text.contains("\n")) 2 else 1,
                modifier = modifier,
            )
        }

        is StreamingService.Display.SymbolText -> {
            Text(
                text = display.text,
                fontSize = (diameter * 0.55f).value.sp,
                fontWeight = FontWeight.Bold,
                color = display.color,
                textAlign = TextAlign.Center,
                maxLines = 1,
                softWrap = false,
                modifier = modifier,
            )
        }

        is StreamingService.Display.Star -> {
            Icon(
                imageVector = Icons.Filled.Star,
                contentDescription = null,
                tint = Color(red = 0xFF, green = 0xC8, blue = 0x1E),
                modifier = modifier.size(diameter * 0.55f),
            )
        }
    }
}
