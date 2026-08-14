package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
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
    topInset: Dp = 12.dp,
    bottomInset: Dp = 12.dp,
) {
    // Watchdog: if a scroll request never settles (no host handles it),
    // force-settle after 1.2s so the overlay can never hang invisibly.
    LaunchedEffect(manager.isShowing, manager.currentMark?.key) {
        if (!manager.isShowing) return@LaunchedEffect
        delay(1200)
        if (manager.isShowing && !manager.scrollSettled) {
            manager.markScrollSettled()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        CoachMarkSpotlight(
            manager = manager,
            topInset = topInset,
            bottomInset = bottomInset,
        )

        AnimatedVisibility(
            visible = manager.completionToastVisible,
            enter = slideInVertically { it } + fadeIn(),
            exit = slideOutVertically { it } + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .padding(horizontal = 20.dp, vertical = 0.dp)
                    .padding(bottom = 86.dp)
                    .background(BrandOrange, RoundedCornerShape(14.dp))
                    .padding(horizontal = 16.dp, vertical = 12.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.CheckCircle,
                    contentDescription = null,
                    tint = Navy,
                    modifier = Modifier.size(18.dp),
                )
                Text(
                    text = "You're set. Tap any poster and we'll show you the rest.",
                    fontSize = 13.sp,
                    lineHeight = 19.sp,
                    fontWeight = FontWeight.Medium,
                    color = Navy,
                )
            }
        }
    }
}

/**
 * The actual spotlight surface: dimmed scrim with holes, pulse rings and
 * callout card. Kept identical to the previous implementation.
 */
@Composable
private fun CoachMarkSpotlight(
    manager: CoachMarkManager,
    topInset: Dp,
    bottomInset: Dp,
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
    val topInsetPx = with(density) { topInset.toPx() }
    val bottomInsetPx = with(density) { bottomInset.toPx() }
    val radius14 = with(density) { 14.dp.toPx() }
    val stroke2 = with(density) { 2.dp.toPx() }
    val cardWidthPx = with(density) { 230.dp.toPx() }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { manager.advance() }
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
    ) {
        // Scrim with holes — single Canvas draws all holes from one mask using
        // BlendMode.Clear so the underlying UI remains visible, framed only by
        // the orange pulse rings below.
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
        ) {
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
                        color = Color.Transparent,
                        radius = dim / 2f,
                        center = Offset(cx, cy),
                        blendMode = BlendMode.Clear,
                    )
                } else {
                    drawRoundRect(
                        color = Color.Transparent,
                        topLeft = expanded.topLeft,
                        size = expanded.size,
                        cornerRadius = CornerRadius(radius14, radius14),
                        blendMode = BlendMode.Clear,
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
            topInset = topInset,
            bottomInset = bottomInset,
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
    topInset: Dp,
    bottomInset: Dp,
    cardWidthPx: Float,
    density: androidx.compose.ui.unit.Density,
) {
    val lowestBottom = allRects.maxOf { it.bottom }
    val highestTop = allRects.minOf { it.top }
    val midScreen = screenRect.center.y
    val belowCard = lowestBottom < midScreen

    var cardHeightPx by remember { mutableFloatStateOf(140f) }

    // Narrow screens must not push the card off either edge, so the nominal
    // width collapses to whatever the screen can actually hold.
    val maxCardWidthPx = (screenRect.width - padding10 * 2f).coerceAtLeast(0f)
    val actualCardWidthPx = cardWidthPx.coerceAtMost(maxCardWidthPx)
    val cardWidthDp = with(density) { actualCardWidthPx.toDp() }

    var rawX = anchorRect.center.x - actualCardWidthPx / 2f
    rawX = rawX.coerceIn(
        padding10,
        (screenRect.width - actualCardWidthPx - padding10).coerceAtLeast(padding10),
    )

    val topInsetPx = with(density) { topInset.toPx() }
    val bottomInsetPx = with(density) { bottomInset.toPx() }

    val preferredTop = if (belowCard) {
        lowestBottom + padding12
    } else {
        highestTop - padding12 - cardHeightPx
    }
    // The card is positioned manually, so nothing else keeps it on screen:
    // clamp its top edge to the safe band. Without this a tall card anchored
    // near an edge (or a target close to the bottom) runs off the display.
    val minTop = topInsetPx.coerceAtLeast(padding12)
    val maxTop = (screenRect.height - cardHeightPx - bottomInsetPx)
        .coerceAtLeast(minTop)
    val cardTop = preferredTop.coerceIn(minTop, maxTop)

    Box(
        modifier = Modifier
            .offset {
                IntOffset(
                    rawX.roundToInt(),
                    cardTop.roundToInt(),
                )
            }
            .width(cardWidthDp)
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
    ) {
        Column(
            modifier = Modifier
                .width(cardWidthDp)
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
            // fillMaxWidth, never fillMaxSize: inside a wrap-height Column a
            // fillMaxSize footer stretches the card to the full screen height,
            // which is what made the callout a giant orange slab.
            Row(
                modifier = Modifier.fillMaxWidth(),
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
                        text = if (manager.currentIndex == manager.activeTour.size - 1) "Done" else "Next",
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
