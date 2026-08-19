package com.rork.guidestreamtvandroid.ui.components

import android.provider.Settings
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SportsSoccer
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.SportsSoccer
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.repository.CoachMarkManager
import com.rork.guidestreamtvandroid.data.repository.ReelsBadgeService
import com.rork.guidestreamtvandroid.ui.navigation.AppTab
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.SurfaceContainer
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Floating glass tab bar with Home, Reels, Sports, Profile + detached Ask FAB.
 * Mirrors iOS FloatingTabBar.
 */
@Composable
fun FloatingTabBar(
    selected: AppTab,
    onTabSelected: (AppTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    val coachMark = CoachMarkManager.get()
    val density = LocalDensity.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp)
            .padding(bottom = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Glass pill with 4 tabs
        Row(
            modifier = Modifier
                .weight(1f)
                .height(64.dp)
                .shadow(6.dp, RoundedCornerShape(32.dp), clip = false)
                .clip(RoundedCornerShape(32.dp))
                .background(SurfaceContainer)
                .border(1.dp, OutlineVariant, RoundedCornerShape(32.dp))
                .padding(horizontal = 6.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TabItem(AppTab.HOME, selected == AppTab.HOME) { onTabSelected(it) }
            Box(modifier = Modifier.onGloballyPositioned { coords ->
                coachMark.setMeasuredRect("reels", coords.boundsInRoot())
            }) {
                TabItem(AppTab.REELS, selected == AppTab.REELS) { onTabSelected(it) }
            }
            Box(modifier = Modifier.onGloballyPositioned { coords ->
                coachMark.setMeasuredRect("sports", coords.boundsInRoot())
            }) {
                TabItem(AppTab.SPORTS, selected == AppTab.SPORTS) { onTabSelected(it) }
            }
            TabItem(AppTab.PROFILE, selected == AppTab.PROFILE) { onTabSelected(it) }
        }

        // Ask FAB
        Box(modifier = Modifier.onGloballyPositioned { coords ->
            coachMark.setMeasuredRect("ask", coords.boundsInRoot())
        }) {
            AskFab(onClick = { onTabSelected(AppTab.ASK) })
        }
    }
}

@Composable
private fun TabItem(
    tab: AppTab,
    isSelected: Boolean,
    onClick: (AppTab) -> Unit,
) {
    val (filled, outlined) = tabIconPair(tab)
    val reelsBadge = ReelsBadgeService.get()
    val hasUnseen by reelsBadge.hasUnseen.collectAsStateWithLifecycle()
    val showBadge = tab == AppTab.REELS && hasUnseen && !isSelected

    val animatorScale = Settings.Global.getFloat(
        LocalContext.current.contentResolver,
        Settings.Global.ANIMATOR_DURATION_SCALE,
        1f,
    )
    val targetScale = if (showBadge) 1f else 0f
    val scale by animateFloatAsState(
        targetValue = targetScale,
        animationSpec = if (animatorScale == 0f) snap() else spring(dampingRatio = 0.62f, stiffness = 0.34f),
        label = "reels_badge_scale",
    )

    Column(
        modifier = Modifier
            .clickable(
                interactionSource = MutableInteractionSource(),
                indication = null,
            ) { onClick(tab) }
            .padding(vertical = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            contentAlignment = Alignment.TopEnd,
        ) {
            Icon(
                imageVector = if (isSelected) filled else outlined,
                contentDescription = tab.title,
                tint = if (isSelected) BrandOrange else TextTertiary,
                modifier = Modifier.size(22.dp),
            )
            if (showBadge) {
                Box(
                    modifier = Modifier
                        .graphicsLayer {
                            scaleX = scale
                            scaleY = scale
                        }
                        .offset(x = 5.dp, y = (-4).dp)
                        .size(13.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF0A121B)),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        modifier = Modifier
                            .size(9.dp)
                            .clip(CircleShape)
                            .background(BrandBlue),
                    )
                }
            }
        }
        Spacer(Modifier.height(2.dp))
        Text(
            text = tab.title,
            fontSize = 10.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (isSelected) TextPrimary.copy(alpha = 0.92f) else TextTertiary,
            maxLines = 1,
        )
        Spacer(Modifier.height(2.dp))
        Box(
            modifier = Modifier
                .size(4.dp)
                .clip(CircleShape)
                .background(if (isSelected) BrandOrange else Color.Transparent),
        )
    }
}

@Composable
private fun AskFab(onClick: () -> Unit) {
    // Pulsing glow
    val transition = rememberInfiniteTransition(label = "fab_glow")
    val glowAlpha by transition.animateFloat(
        initialValue = 0.08f,
        targetValue = 0.24f,
        animationSpec = infiniteRepeatable(
            animation = tween(1550),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "glow_alpha",
    )

    Box(contentAlignment = Alignment.Center) {
        // Glow
        Box(
            modifier = Modifier
                .size(66.dp)
                .clip(CircleShape)
                .background(BrandOrange.copy(alpha = glowAlpha)),
        )
        // FAB button
        Box(
            modifier = Modifier
                .size(54.dp)
                .clip(CircleShape)
                .background(
                    Brush.verticalGradient(
                        colors = listOf(BrandOrange, BrandOrange.copy(red = 0.95f, green = 0.42f, blue = 0.05f)),
                    ),
                )
                .border(1.dp, Color.White.copy(alpha = 0.30f), CircleShape)
                .clickable(
                    interactionSource = MutableInteractionSource(),
                    indication = null,
                ) { onClick() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.AutoAwesome,
                contentDescription = "Ask Stream",
                tint = Color.White,
                modifier = Modifier.size(22.dp),
            )
        }
    }
}

private fun tabIconPair(tab: AppTab): Pair<ImageVector, ImageVector> = when (tab) {
    AppTab.HOME -> Icons.Filled.Home to Icons.Outlined.Home
    AppTab.REELS -> Icons.Filled.PlayArrow to Icons.Outlined.PlayArrow
    AppTab.SPORTS -> Icons.Filled.SportsSoccer to Icons.Outlined.SportsSoccer
    AppTab.PROFILE -> Icons.Filled.Person to Icons.Outlined.Person
    AppTab.ASK -> Icons.Filled.AutoAwesome to Icons.Filled.AutoAwesome
}
