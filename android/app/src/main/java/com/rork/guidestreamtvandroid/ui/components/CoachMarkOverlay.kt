package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.repository.CoachMark
import com.rork.guidestreamtvandroid.data.repository.CoachMarkManager
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Navy
import kotlin.math.roundToInt

private val ScrimColor = Navy.copy(alpha = 0.57f)
private val RingColor = BrandOrange
private val CardColor = BrandOrange
private val CardTextColor = Navy
private val CardBodyColor = Navy.copy(alpha = 0.72f)
private val InactiveDotColor = Navy.copy(alpha = 0.30f)

/**
 * Spotlight overlay that dims the screen, cuts holes around one or two
 * real UI elements, and shows a callout card. Mirrors iOS CoachMarkOverlay.
 *
 * Drawn with a Canvas inside Modifier.graphicsLayer with
 * CompositingStrategy.Offscreen so BlendMode.Clear punches holes correctly.
 */
@Composable
fun CoachMarkOverlay(
    manager: CoachMarkManager,
    modifier: Modifier = Modifier,
) {
    if (!manager.isShowing) return
    val mark = manager.currentMark ?: return
    if (!manager.scrollSettled) return

    val validRects = mark.targetKeys.mapNotNull { key ->
        manager.measuredRects[key]?.takeIf { !it.isEmpty }?.let { key to it }
    }

    if (validRects.isEmpty()) return

    val cutoutRects = validRects.map { it.second }
    val firstRect = validRects.first().second
    val density = LocalDensity.current
    val configuration = LocalConfiguration.current
    val screenWidthPx = with(density) { configuration.screenWidthDp.dp.toPx() }
    val screenHeightPx = with(density) { configuration.screenHeightDp.dp.toPx() }
    val screenRect = Rect(offset = Offset.Zero, size = Size(screenWidthPx, screenHeightPx))

    val padding8 = with(density) { 8.dp.toPx() }
    val padding12 = with(density) { 12.dp.toPx() }
    val padding10 = with(density) { 10.dp.toPx() }
    val radius14 = with(density) { 14.dp.toPx() }
    val stroke2 = with(density) { 2.dp.toPx() }
    val cardWidthPx = with(density) { 230.dp.toPx() }

    Box(
        modifier = modifier
            .fillMaxSize()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { manager.advance() }
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
    ) {
        // Scrim with holes — single Canvas draws all holes from one mask
        Canvas(modifier = Modifier.fillMaxSize()) {
            drawRect(color = ScrimColor, size = size)
            cutoutRects.forEach { rect ->
                val expanded = Rect(
                    offset = Offset(
                        (rect.left - padding8).coerceAtLeast(0f),
                        (rect.top - padding8).coerceAtLeast(0f),
                    ),
                    size = Size(
                        rect.width + padding8 * 2,
                        rect.height + padding8 * 2,
                    ),
                )
                if (mark.isCircular) {
                    val dim = maxOf(expanded.width, expanded.height)
                    val cx = expanded.center.x
                    val cy = expanded.center.y
                    drawCircle(
                        color = Color.White,
                        radius = dim / 2f,
                        center = Offset(cx, cy),
                    )
                } else {
                    drawRoundRect(
                        color = Color.White,
                        topLeft = expanded.topLeft,
                        size = expanded.size,
                        cornerRadius = CornerRadius(radius14, radius14),
                    )
                }
            }
        }

        // Pulse rings around each cutout
        cutoutRects.forEach { rect ->
            PulseRing(
                rect = rect,
                isCircular = mark.isCircular,
                padding8 = padding8,
                radius14 = radius14,
                stroke2 = stroke2,
                density = density,
            )
        }

        // Callout card
        CalloutCard(
            mark = mark,
            anchorRect = firstRect,
            allRects = cutoutRects,
            screenRect = screenRect,
            index = manager.currentIndex,
            total = manager.activeTour.size,
            manager = manager,
            padding8 = padding8,
            padding10 = padding10,
            padding12 = padding12,
            cardWidthPx = cardWidthPx,
            density = density,
        )
    }
}

@Composable
private fun PulseRing(
    rect: Rect,
    isCircular: Boolean,
    padding8: Float,
    radius14: Float,
    stroke2: Float,
    density: androidx.compose.ui.unit.Density,
) {
    val transition = rememberInfiniteTransition(label = "coach_pulse")
    val pulseAlpha by transition.animateFloat(
        initialValue = 0.9f,
        targetValue = 0.15f,
        animationSpec = infiniteRepeatable(
            animation = tween(850),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulse_alpha",
    )

    val expanded = Rect(
        offset = Offset(
            (rect.left - padding8).coerceAtLeast(0f),
            (rect.top - padding8).coerceAtLeast(0f),
        ),
        size = Size(
            rect.width + padding8 * 2,
            rect.height + padding8 * 2,
        ),
    )

    Canvas(
        modifier = Modifier
            .offset {
                IntOffset(
                    expanded.left.roundToInt(),
                    expanded.top.roundToInt(),
                )
            }
            .size(
                width = with(density) { expanded.width.toDp() },
                height = with(density) { expanded.height.toDp() },
            ),
    ) {
        if (isCircular) {
            val dim = maxOf(size.width, size.height)
            drawCircle(
                color = RingColor.copy(alpha = pulseAlpha),
                radius = dim / 2f,
                style = Stroke(width = stroke2),
            )
        } else {
            drawRoundRect(
                color = RingColor.copy(alpha = pulseAlpha),
                topLeft = Offset.Zero,
                size = size,
                cornerRadius = CornerRadius(radius14, radius14),
                style = Stroke(width = stroke2),
            )
        }
    }
}

@Composable
private fun CalloutCard(
    mark: CoachMark,
    anchorRect: Rect,
    allRects: List<Rect>,
    screenRect: Rect,
    index: Int,
    total: Int,
    manager: CoachMarkManager,
    padding8: Float,
    padding10: Float,
    padding12: Float,
    cardWidthPx: Float,
    density: androidx.compose.ui.unit.Density,
) {
    val lowestBottom = allRects.maxOf { it.bottom }
    val highestTop = allRects.minOf { it.top }
    val midScreen = screenRect.center.y
    val belowCard = lowestBottom < midScreen

    var cardHeightPx by remember { mutableFloatStateOf(140f) }

    var rawX = anchorRect.center.x - cardWidthPx / 2f
    rawX = rawX.coerceIn(padding10, screenRect.width - cardWidthPx - padding10)

    val cardY = if (belowCard) {
        lowestBottom + padding12 + cardHeightPx / 2f
    } else {
        highestTop - padding12 - cardHeightPx / 2f
    }

    Box(
        modifier = Modifier
            .offset {
                IntOffset(
                    (rawX).roundToInt(),
                    (cardY - cardHeightPx / 2f).roundToInt(),
                )
            }
            .width(230.dp)
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
    ) {
        Column(
            modifier = Modifier
                .width(230.dp)
                .background(CardColor, RoundedCornerShape(12.dp))
                .padding(horizontal = 14.dp, vertical = 12.dp)
                .onGloballyPositioned { coords ->
                    cardHeightPx = coords.size.height.toFloat()
                },
        ) {
            Text(
                text = mark.title,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = CardTextColor,
            )
            Spacer(Modifier.size(4.dp))
            Text(
                text = mark.body,
                fontSize = 12.sp,
                lineHeight = 18.sp,
                color = CardBodyColor,
            )
            Spacer(Modifier.size(10.dp))
            Row(
                modifier = Modifier.fillMaxSize(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (i in 0 until total) {
                        Box(
                            modifier = Modifier
                                .size(5.dp)
                                .background(
                                    if (i == index) CardTextColor else InactiveDotColor,
                                    CircleShape,
                                ),
                        )
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "Skip",
                        fontSize = 11.sp,
                        color = CardTextColor.copy(alpha = 0.72f),
                        modifier = Modifier.clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { manager.skipTour() },
                    )
                    Spacer(Modifier.size(8.dp))
                    Text(
                        text = if (mark.isLastInTour) "Done" else "Next",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = CardTextColor,
                        modifier = Modifier.clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { manager.advance() },
                    )
                }
            }
        }
    }
}
