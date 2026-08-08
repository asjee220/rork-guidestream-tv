package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Text
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary

/** Base fill for shimmer cards — matches iOS ShimmerView (RemoteImage.swift). */
private val ShimmerBase = Color(0xFF0D1623)

/** Travelling highlight band — matches iOS ShimmerView. */
private val ShimmerHighlight = Color(0xFF1A2535)

/**
 * Shimmer placeholder block — mirrors the iOS ShimmerView: a travelling
 * linear-gradient highlight that sweeps left→right over a fixed base fill,
 * restarting (never reversing) every 1200ms with linear easing. [phase]
 * offsets the sweep so sibling placeholders read as a wave instead of moving
 * in lockstep.
 */
@Composable
fun ShimmerBox(
    modifier: Modifier = Modifier,
    cornerRadius: Int = 8,
    phase: Float = 0f,
) {
    val transition = rememberInfiniteTransition(label = "shimmer")
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1200, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "shimmer_sweep",
    )
    val shape = RoundedCornerShape(cornerRadius.dp)
    Box(
        modifier = modifier
            .clip(shape)
            .drawBehind {
                drawRect(ShimmerBase)
                val t = (progress + phase) % 1f
                val band = size.width * 0.6f
                val startX = -band + (size.width + band * 2f) * t
                drawRect(
                    brush = Brush.linearGradient(
                        colors = listOf(ShimmerBase, ShimmerHighlight, ShimmerBase),
                        start = Offset(startX, 0f),
                        end = Offset(startX + band, size.height),
                    ),
                )
            }
            .border(1.dp, GlassStroke, shape),
    )
}

/**
 * Shimmer section — renders the REAL section title (identically to
 * PosterSection's title row) above five poster-sized placeholders matching
 * PosterCardWithBadge geometry (164dp × 0.6667 aspect, 10dp radius), so the
 * swap to real content produces zero layout shift. Adds no padding of its
 * own — call sites pass `Modifier.padding(horizontal = 12.dp, vertical = 8.dp)`.
 */
@Composable
fun ShimmerSection(
    title: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
    ) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = title,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Spacer(Modifier.width(6.dp))
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(BrandOrange)
                    .align(Alignment.Bottom),
            )
        }
        Spacer(Modifier.height(10.dp))
        // Non-scrollable, non-interactive row clipped at the screen edge; the
        // unbounded wrap lets all five 164dp cards lay out at full size so
        // the visible ones match the real rail exactly.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clipToBounds()
                .wrapContentWidth(align = Alignment.Start, unbounded = true),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            repeat(5) { index ->
                ShimmerBox(
                    modifier = Modifier
                        .width(164.dp)
                        .aspectRatio(0.6667f),
                    cornerRadius = 10,
                    phase = index * 0.12f,
                )
            }
        }
    }
}

/**
 * Hero shimmer — three placeholders matching the real HeroCarousel card
 * geometry (280dp × 1.7 aspect, 16dp radius). Adds no padding of its own —
 * HomeScreen wraps it in a Box with 12dp/8dp padding.
 */
@Composable
fun ShimmerHero() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clipToBounds()
            .wrapContentWidth(align = Alignment.Start, unbounded = true),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        repeat(3) { index ->
            ShimmerBox(
                modifier = Modifier
                    .width(280.dp)
                    .aspectRatio(1.7f),
                cornerRadius = 16,
                phase = index * 0.15f,
            )
        }
    }
}
