package com.rork.guidestreamtvandroid.ui.components

import android.provider.Settings
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Entrance motion for the detail sheet and the full-details screen, matching
 * `ios/GuideStreamTV/Views/SheetLoadingMotion.swift` beat for beat. Two ideas:
 *
 * A — Reserved Frame. The "Where to Watch" row is mounted at its final height
 *     for the whole lookup, so the CTA and everything below it never move when
 *     the sources land.
 *
 * B — Service Lock-On. While the lookup runs the chips flick through real brand
 *     marks, decelerating as it ages; on resolve they snap with a spring, a rim
 *     flash and a single light haptic. The watch CTA drops its spinner for a
 *     sheen that travels the button.
 *
 * Everything collapses to a static placeholder and an instant swap when the
 * device has animations turned off.
 *
 * Spec: claude/detail-sheet-motion-spec-aug2026.md
 */
object SheetMotion {
    const val BREATHE_MS = 900          // half-period; Reverse gives 1.8s
    const val PATIENCE_MS = 4_000L      // a lookup is "slow" past this
    const val SHEEN_MS = 1_150
    const val SHUFFLE_START_MS = 110L
    const val SHUFFLE_SLOW_MS = 190L
    const val LOCK_STAGGER_MS = 80L

    /** Placeholder chip name-bar widths — uneven, so the row reads as content. */
    val placeholderWidths = listOf(72.dp, 56.dp, 88.dp)

    /**
     * Real US services the shuffle cycles through. Every one resolves through
     * [Platform.from], so a flick frame never renders as an unbranded grey.
     */
    val shufflePool = listOf(
        "Netflix", "Paramount+", "Max", "Hulu",
        "Prime Video", "Peacock", "Disney+", "Apple TV+",
    )

    fun shuffleName(frame: Int, seed: Int): String =
        shufflePool[((frame + seed * 3) % shufflePool.size + shufflePool.size) % shufflePool.size]
}

/** True when the device has animations turned off (developer options or a11y). */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f
    }
}

/**
 * Breathing alpha for pending placeholders: 0.55 → 0.85 and back on a 1.8s
 * cycle. Deliberately not a travelling shimmer — a sweeping highlight is a web
 * idiom, and it reads as decoration rather than as work in progress.
 */
@Composable
fun breatheAlpha(): Float {
    if (rememberReduceMotion()) return 0.70f
    val transition = rememberInfiniteTransition(label = "breathe")
    val alpha by transition.animateFloat(
        initialValue = 0.55f,
        targetValue = 0.85f,
        animationSpec = infiniteRepeatable(
            animation = tween(SheetMotion.BREATHE_MS),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "breathe_alpha",
    )
    return alpha
}

/**
 * Frame counter for the brand-mark shuffle. Starts at 110ms a frame and
 * decelerates toward 190ms as the lookup ages, so a long wait slows down
 * instead of strobing.
 */
@Composable
fun rememberShuffleFrame(): Int {
    if (rememberReduceMotion()) return 0
    var frame by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        var elapsed = 0L
        while (true) {
            val step = (SheetMotion.SHUFFLE_START_MS + elapsed / 50)
                .coerceAtMost(SheetMotion.SHUFFLE_SLOW_MS)
            delay(step)
            elapsed += step
            frame++
        }
    }
    return frame
}

/** Scale + rim-flash values produced by a lock-on. */
data class LockOnState(val scale: Float, val rimAlpha: Float)

/**
 * Snap-to-resolved: spring overshoot to 1.06, a rim flash at 45% white, then
 * settle. One-shot — the CTA's resolving flag legitimately flips back to true
 * while the episode-level deep link resolves, and locking twice would read as a
 * stutter and fire the haptic twice for one answer. [haptic] is passed true by
 * exactly one element per resolve.
 */
@Composable
fun rememberLockOn(
    resolved: Boolean,
    delayMs: Long = 0L,
    haptic: Boolean = false,
): LockOnState {
    val reduceMotion = rememberReduceMotion()
    val scale = remember { Animatable(1f) }
    val rim = remember { Animatable(0f) }
    var fired by remember { mutableStateOf(false) }
    val view = LocalView.current

    LaunchedEffect(resolved) {
        if (!resolved || fired || reduceMotion) return@LaunchedEffect
        fired = true
        if (delayMs > 0) delay(delayMs)
        if (haptic) view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
        launch {
            scale.animateTo(1.06f, spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessMediumLow))
            scale.animateTo(1f, spring(dampingRatio = 0.75f, stiffness = Spring.StiffnessMediumLow))
        }
        rim.animateTo(0.45f, tween(160))
        rim.animateTo(0f, tween(200))
    }
    return LockOnState(scale.value, rim.value)
}

/**
 * Pending stand-in for a service chip. Mirrors WhereToWatchChip's geometry —
 * 12dp radius, 14/10 padding, 8dp dot, 14sp name — so the strip holds its
 * height and nothing below it moves when the real chips arrive.
 */
@Composable
fun PendingServiceChip(nameWidth: Dp) {
    val alpha = breatheAlpha()
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White.copy(alpha = 0.06f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(12.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.12f * alpha + 0.04f)),
            )
            Spacer(Modifier.width(8.dp))
            Box(
                modifier = Modifier
                    .width(nameWidth)
                    .height(17.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(Color.White.copy(alpha = 0.14f * alpha + 0.04f)),
            )
        }
    }
}

/**
 * Chip-shaped slot that flicks through real brand marks while the lookup runs.
 * Same size as the loaded chip, so B never costs a layout shift to buy.
 */
@Composable
fun ShufflingServiceChip(seed: Int) {
    if (rememberReduceMotion()) {
        PendingServiceChip(SheetMotion.placeholderWidths[seed % SheetMotion.placeholderWidths.size])
        return
    }
    val frame = rememberShuffleFrame()
    val name = SheetMotion.shuffleName(frame, seed)
    val color = Platform.from(name)?.color ?: BrandOrange
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .background(color.copy(alpha = 0.18f * 0.72f))
            .border(1.dp, color.copy(alpha = 0.45f * 0.72f), RoundedCornerShape(12.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(color.copy(alpha = 0.72f)),
            )
            Spacer(Modifier.width(8.dp))
            Text(
                text = name,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary.copy(alpha = 0.72f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** Three shuffling chips at the exact height of the loaded row. */
@Composable
fun PendingWhereToWatchStrip(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        repeat(3) { i -> ShufflingServiceChip(seed = i) }
    }
}

/**
 * Replaces the spinner inside the orange watch capsule. A highlight band travels
 * the button once every 1.15s: the same "something is happening" signal, but it
 * belongs to the button instead of sitting on top of it. Drop this into the
 * capsule's Box as a `fillMaxSize` sibling behind the label.
 */
@Composable
fun CtaSheen(modifier: Modifier = Modifier) {
    if (rememberReduceMotion()) return
    val transition = rememberInfiniteTransition(label = "cta_sheen")
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(SheetMotion.SHEEN_MS, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "cta_sheen_travel",
    )
    Box(
        modifier = modifier
            .fillMaxSize()
            .drawBehind {
                val band = size.width * 0.44f
                val startX = -band + (size.width + band * 2f) * progress
                drawRect(
                    brush = Brush.linearGradient(
                        colors = listOf(
                            Color.Transparent,
                            Color.White.copy(alpha = 0.30f),
                            Color.Transparent,
                        ),
                        start = Offset(startX, 0f),
                        end = Offset(startX + band, 0f),
                    ),
                )
            },
    )
}

/**
 * CTA label while a lookup is in flight. Softens to "Still looking…" past four
 * seconds, so a slow network gets an honest answer instead of a sentence that
 * stopped being true three seconds ago.
 */
@Composable
fun ResolvingCtaLabel(fontSize: Int = 15) {
    var slow by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(SheetMotion.PATIENCE_MS)
        slow = true
    }
    Text(
        text = if (slow) "Still looking…" else "Finding service…",
        fontSize = fontSize.sp,
        fontWeight = FontWeight.Bold,
        color = Color.White,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
}
