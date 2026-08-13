package com.rork.guidestreamtvandroid.ui.onboarding

import android.Manifest
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.StreamingService
import com.rork.guidestreamtvandroid.data.models.selectionAccent
import com.rork.guidestreamtvandroid.data.models.selectionGlyphColor
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.PushTokenManager
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.theme.BrandBackground
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.BrandWordmark
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.Hairline
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.SurfaceContainer
import com.rork.guidestreamtvandroid.ui.theme.SurfaceDark
import com.rork.guidestreamtvandroid.ui.theme.SheetSurfaceBase
import com.rork.guidestreamtvandroid.ui.theme.SheetLevel
import com.rork.guidestreamtvandroid.ui.components.GsSheetDragHandle
import com.rork.guidestreamtvandroid.ui.components.GsSheetHeader
import com.rork.guidestreamtvandroid.ui.theme.sheetTopInset
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.sin

/**
 * Onboarding flow — Welcome → Services → Watching now → Creators → Notify → home.
 * 4 counted steps (Services, Watching Now, Creators, Notify) shown in the indicator.
 */
@Composable
fun OnboardingFlow(
    startStep: Int = 0,
    onFinish: () -> Unit,
    onWidgetSettings: () -> Unit = {},
) {
    var step by remember { mutableStateOf(startStep) }
    var showEmailAuth by remember { mutableStateOf(false) }
    var showWidgetSheet by remember { mutableStateOf(false) }
    val auth = AuthViewModel.get()
    val isAuthenticated by auth.isAuthenticated.collectAsState()
    val streams = StreamsViewModel.get()

    LaunchedEffect(isAuthenticated) {
        if (isAuthenticated && step == 0) step = 1
    }
    val selectedServices = remember { mutableStateOf(auth.selectedServices.value) }
    LaunchedEffect(auth.selectedServices) {
        auth.selectedServices.collect { services ->
            if (selectedServices.value != services) selectedServices.value = services
        }
    }
    var pushOn by remember { mutableStateOf(auth.notifyPushEnabled.value) }

    var followedShowPosters by remember { mutableStateOf<List<String>>(emptyList()) }
    var followedShowsCount by remember { mutableStateOf(0) }
    var followedCreatorsCount by remember { mutableStateOf(0) }

    val totalSteps = OnboardingHeader.stepNames.size

    val finish: () -> Unit = {
        if (!auth.isAuthenticated.value) auth.continueAsGuest()
        auth.completeOnboarding()
        onFinish()
    }

    val commitSeeds: (List<StreamSeed>) -> Unit = { seeds ->
        seeds.forEach { seed ->
            streams.addToMyStreams(
                titleId = seed.titleId,
                title = seed.title,
                posterUrl = seed.posterUrl,
                platform = seed.platform,
            )
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        AnimatedContent(
            targetState = step,
            transitionSpec = {
                (slideInHorizontally(tween(350)) { it } + fadeIn(tween(350))) togetherWith
                    (slideOutHorizontally(tween(350)) { -it } + fadeOut(tween(350)))
            },
            label = "onboarding",
        ) { currentStep ->
            when (currentStep) {
                0 -> WelcomeScreen(
                    onContinue = { step = 1 },
                    onEmailAuth = { showEmailAuth = true },
                    onGuest = {
                        auth.continueAsGuest()
                        step = 1
                    },
                )
                1 -> ConnectServicesScreen(
                    selected = selectedServices.value,
                    onToggle = { id ->
                        selectedServices.value = if (id in selectedServices.value) {
                            selectedServices.value - id
                        } else {
                            selectedServices.value + id
                        }
                    },
                    onContinue = {
                        auth.setSelectedServices(selectedServices.value)
                        step = 2
                    },
                    onSkip = {
                        auth.setSelectedServices(selectedServices.value)
                        step = 2
                    },
                )
                2 -> WatchingNowScreen(
                    selectedServices = selectedServices.value,
                    onContinue = { seeds ->
                        followedShowsCount = seeds.size
                        followedShowPosters = seeds.mapNotNull { it.posterUrl }
                        commitSeeds(seeds)
                        step = 3
                    },
                    onSkip = { step = 3 },
                    onBack = { step = 2 },
                    onSkipAll = { finish() },
                    currentStep = 2,
                    totalSteps = totalSteps,
                )
                3 -> FollowCreatorsOnboardingScreen(
                    onContinue = { seeds ->
                        followedCreatorsCount = seeds.size
                        commitSeeds(seeds)
                        step = 4
                    },
                    onSkip = { finish() },
                    onBack = { step = 3 },
                    onSkipAll = { finish() },
                    currentStep = 3,
                    totalSteps = totalSteps,
                )
                else -> StayNotifiedScreen(
                    pushOn = pushOn,
                    onPushToggle = { pushOn = it },
                    onContinue = {
                        auth.setNotificationPreferences(pushOn, false)
                        finish()
                    },
                    onBack = { step = 4 },
                    onWidgetSettings = { showWidgetSheet = true },
                    currentStep = 4,
                    totalSteps = totalSteps,
                    posterUrls = followedShowPosters,
                    showCount = followedShowsCount,
                    creatorCount = followedCreatorsCount,
                )
            }
        }

        if (showWidgetSheet) {
            WidgetInstructionSheet(onDismiss = { showWidgetSheet = false })
        }

        if (showEmailAuth) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Navy)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { },
            ) {
                EmailAuthScreen(
                    onAuthenticated = {
                        showEmailAuth = false
                        if (!auth.hasCompletedOnboarding.value) {
                            step = 1
                        }
                    },
                    onClose = { showEmailAuth = false },
                )
            }
        }
    }
}

// ── Welcome ───────────────────────────────────────────────────────

@Composable
private fun WelcomeScreen(
    onContinue: () -> Unit,
    onEmailAuth: () -> Unit,
    onGuest: () -> Unit,
) {
    val auth = AuthViewModel.get()
    val isAuthenticating by auth.isAuthenticating.collectAsState()
    val lastError by auth.lastError.collectAsState()
    val context = LocalContext.current
    val reduceMotion = remember {
        Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f
    }

    Box(modifier = Modifier.fillMaxSize()) {
        BrandBackground(modifier = Modifier.fillMaxSize())

        // Ambient drifting blurred poster wall — above the navy base, below the
        // wordmark, hairline, and glass card. Purely computed gradients.
        DriftingPosterWall(
            reduceMotion = reduceMotion,
            modifier = Modifier.fillMaxSize(),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Spacer(Modifier.height(24.dp))

            Box(contentAlignment = Alignment.Center) {
                BrandWordmark(size = com.rork.guidestreamtvandroid.ui.theme.WordmarkSize.LARGE)
                if (!reduceMotion) {
                    TuningShimmer()
                }
            }
            Spacer(Modifier.height(8.dp))

            Box(
                modifier = Modifier
                    .width(260.dp)
                    .height(2.dp)
                    .background(
                        Brush.horizontalGradient(
                            colors = listOf(
                                BrandBlue.copy(alpha = 0f),
                                BrandBlue,
                                BrandOrange,
                                BrandOrange.copy(alpha = 0f),
                            ),
                        ),
                    ),
            )
            Spacer(Modifier.height(32.dp))

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(20.dp))
                    .background(GlassFill)
                    .border(1.dp, GlassStroke, RoundedCornerShape(20.dp))
                    .padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = "Every show. Every service.",
                    fontSize = 13.sp,
                    color = TextSecondary,
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Clip,
                )
                Text(
                    text = "What are you watching now?",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    color = TextPrimary,
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Clip,
                )
                Spacer(Modifier.height(16.dp))

                AuthButton(
                    text = "Sign in with Google",
                    background = Color.White,
                    textColor = Color(red = 0.24f, green = 0.24f, blue = 0.26f),
                    isLoading = isAuthenticating,
                    onClick = { auth.signInWithGoogle(context) },
                )
                Spacer(Modifier.height(12.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(1.dp)
                            .background(Hairline),
                    )
                    Text(
                        text = "or",
                        fontSize = 12.sp,
                        color = TextSecondary,
                        modifier = Modifier.padding(horizontal = 10.dp),
                    )
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(1.dp)
                            .background(Hairline),
                    )
                }
                Spacer(Modifier.height(12.dp))

                OutlinedAuthButton(
                    text = "Sign in with email",
                    icon = Icons.Filled.Email,
                    onClick = onEmailAuth,
                )

                Spacer(Modifier.height(8.dp))
                Text(
                    text = "Continue as guest",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = TextSecondary,
                    modifier = Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onGuest() }
                        .padding(8.dp),
                )

                if (lastError != null) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        text = lastError ?: "",
                        fontSize = 11.sp,
                        color = Color.Red.copy(alpha = 0.85f),
                        textAlign = TextAlign.Center,
                    )
                }

                Spacer(Modifier.height(8.dp))
                Text(
                    text = buildAnnotatedString {
                        append("By continuing, you agree to our ")
                        withLink(LinkAnnotation.Url("https://guidestream.tv/privacy")) {
                            withStyle(SpanStyle(color = BrandBlue)) {
                                append("Privacy Policy")
                            }
                        }
                        append(" and ")
                        withLink(LinkAnnotation.Url("https://guidestream.tv/terms")) {
                            withStyle(SpanStyle(color = BrandBlue)) {
                                append("Terms of Service")
                            }
                        }
                        append(".")
                    },
                    fontSize = 13.sp,
                    color = TextTertiary,
                    textAlign = TextAlign.Center,
                )
            }
        }

        ChannelChip(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .statusBarsPadding()
                .padding(top = 8.dp, end = 20.dp),
        )
    }
}

// ── Welcome decorative layers ──────────────────────────────────

/// Ten brand-adjacent poster-tile colors, assigned deterministically by index.
private val posterTileColors: List<Color> = listOf(
    Color(0xFFE50914),
    Color(0xFF1A6FE8),
    Color(0xFF00A8E1),
    Color(0xFF5B2A86),
    Color(0xFFF5821F),
    Color(0xFF0F79AF),
    Color(0xFF772CE8),
    Color(0xFFE4A11B),
    Color(0xFF1DB954),
    Color(0xFF2E51A2),
)

/// Mixes a color slightly toward its gray luminance to gently reduce saturation
/// (mirrors the iOS `.saturation(0.85)` applied to the poster wall).
private fun Color.desaturated(amount: Float): Color {
    val gray = 0.299f * red + 0.587f * green + 0.114f * blue
    return Color(
        red = red + (gray - red) * (1f - amount),
        green = green + (gray - green) * (1f - amount),
        blue = blue + (gray - blue) * (1f - amount),
        alpha = alpha,
    )
}

@Composable
private fun DriftingPosterWall(
    reduceMotion: Boolean,
    modifier: Modifier = Modifier,
) {
    val maskBrush = remember {
        Brush.verticalGradient(
            0.0f to Color.Transparent,
            0.22f to Color.Black,
            0.55f to Color.Black,
            0.92f to Color.Transparent,
        )
    }
    Box(
        modifier = modifier
            .clipToBounds()
            .graphicsLayer {
                alpha = 0.30f
                compositingStrategy = CompositingStrategy.Offscreen
            }
            .drawWithContent {
                drawContent()
                drawRect(brush = maskBrush, blendMode = BlendMode.DstIn)
            },
    ) {
        BoxWithConstraints(modifier = Modifier.fillMaxSize().blur(7.dp)) {
            val columns = 4
            val gap = 8.dp
            val tileW = (maxWidth - gap * (columns - 1)) / columns
            val tileH = tileW * 1.5f
            val rowH = tileH + gap
            val rowsPerCopy = (ceil(maxHeight.value / rowH.value).toInt() + 1).coerceAtLeast(1)
            val copyStride = rowH * rowsPerCopy

            val density = LocalDensity.current
            val wPx = with(density) { tileW.toPx() }
            val hPx = with(density) { tileH.toPx() }

            val transition = rememberInfiniteTransition(label = "posterDrift")
            val f by transition.animateFloat(
                initialValue = 0f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    animation = tween(22000, easing = LinearEasing),
                    repeatMode = RepeatMode.Restart,
                ),
                label = "posterDriftValue",
            )
            val offsetY = if (reduceMotion) 0.dp else -(copyStride * f)

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .offset(y = offsetY),
                verticalArrangement = Arrangement.spacedBy(gap),
            ) {
                PosterTileSet(rowsPerCopy, columns, tileW, tileH, gap, wPx, hPx)
                PosterTileSet(rowsPerCopy, columns, tileW, tileH, gap, wPx, hPx)
            }
        }
    }
}

@Composable
private fun PosterTileSet(
    rows: Int,
    columns: Int,
    tileW: Dp,
    tileH: Dp,
    gap: Dp,
    wPx: Float,
    hPx: Float,
) {
    Column(verticalArrangement = Arrangement.spacedBy(gap)) {
        repeat(rows) { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                repeat(columns) { col ->
                    val idx = row * columns + col
                    val base = posterTileColors[idx % posterTileColors.size].desaturated(0.85f)
                    Box(
                        modifier = Modifier
                            .size(tileW, tileH)
                            .clip(RoundedCornerShape(6.dp))
                            .background(
                                Brush.linearGradient(
                                    colors = listOf(base, Color.Black.copy(alpha = 0.55f)),
                                    start = Offset(wPx * 0.933f, hPx * 0.25f),
                                    end = Offset(wPx * 0.067f, hPx * 0.75f),
                                ),
                            ),
                    )
                }
            }
        }
    }
}

@Composable
private fun TuningShimmer(modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "tuningShimmer")
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(3400, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "tuningShimmerProgress",
    )
    val offsetY = (-32f + 64f * progress).dp
    val opacity = sin(progress * PI).toFloat().coerceIn(0f, 1f)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(22.dp)
            .offset(y = offsetY)
            .graphicsLayer { alpha = opacity }
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        Color.White.copy(alpha = 0f),
                        Color.White.copy(alpha = 0.28f),
                        Color.White.copy(alpha = 0f),
                    ),
                ),
            ),
    )
}

@Composable
private fun ChannelChip(modifier: Modifier = Modifier) {
    Text(
        text = "CH 01",
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 1.sp,
        color = BrandOrange,
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .border(1.dp, BrandOrange.copy(alpha = 0.5f), RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp),
    )
}

@Composable
private fun AuthButton(
    text: String,
    background: Color,
    textColor: Color,
    isLoading: Boolean = false,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(54.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(background)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                enabled = !isLoading,
            ) { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                color = textColor,
                strokeWidth = 2.dp,
            )
        } else {
            Text(
                text = text,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = textColor,
            )
        }
    }
}

@Composable
private fun OutlinedAuthButton(
    text: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .clip(RoundedCornerShape(14.dp))
            .border(1.dp, BrandOrange.copy(alpha = 0.4f), RoundedCornerShape(14.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = BrandOrange.copy(alpha = 0.6f),
            modifier = Modifier.size(16.dp),
        )
        Spacer(Modifier.width(8.dp))
        Text(
            text = text,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            color = BrandOrange.copy(alpha = 0.75f),
        )
    }
}

// ── Connect Services (hybrid layout) ──────────────────────────────

@Composable
private fun ServiceSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var isFocused by remember { mutableStateOf(false) }
    BasicTextField(
        value = query,
        onValueChange = onQueryChange,
        singleLine = true,
        textStyle = TextStyle(color = Color.White, fontSize = 15.sp),
        cursorBrush = SolidColor(BrandOrange),
        modifier = modifier
            .fillMaxWidth()
            .height(44.dp)
            .clip(RoundedCornerShape(50.dp))
            .background(Color.White.copy(alpha = 0.05f))
            .border(
                1.dp,
                if (isFocused) BrandOrange else Color.White.copy(alpha = 0.10f),
                RoundedCornerShape(50.dp),
            )
            .onFocusChanged { isFocused = it.isFocused },
        decorationBox = { innerTextField ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp)
                    .padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Filled.Search,
                    contentDescription = null,
                    tint = TextSecondary,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(8.dp))
                Box(modifier = Modifier.weight(1f)) {
                    if (query.isEmpty()) {
                        Text(
                            text = "Search all services",
                            fontSize = 15.sp,
                            color = TextSecondary,
                        )
                    }
                    innerTextField()
                }
            }
        },
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ConnectServicesScreen(
    selected: Set<String>,
    onToggle: (String) -> Unit,
    onContinue: () -> Unit,
    onSkip: () -> Unit,
) {
    var serviceQuery by remember { mutableStateOf("") }
    val filteredPopular = remember(serviceQuery) {
        if (serviceQuery.isBlank()) StreamingCatalog.popular
        else StreamingCatalog.popular.filter { it.name.contains(serviceQuery, ignoreCase = true) }
    }
    val filteredAll = remember(serviceQuery) {
        if (serviceQuery.isBlank()) StreamingCatalog.alphabetical
        else StreamingCatalog.alphabetical.filter { it.name.contains(serviceQuery, ignoreCase = true) }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        OnboardingHeader(currentStep = 1, totalSteps = OnboardingHeader.stepNames.size)

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp),
        ) {
            Text(
                text = "Which services do you have?",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "Pick every service you have — each one sharpens your feed",
                fontSize = 15.sp,
                color = TextSecondary,
            )
            Spacer(Modifier.height(18.dp))

            ServiceSearchField(
                query = serviceQuery,
                onQueryChange = { serviceQuery = it },
            )
            Spacer(Modifier.height(16.dp))

            if (filteredPopular.isEmpty() && filteredAll.isEmpty()) {
                Text(
                    text = "No services match",
                    fontSize = 14.sp,
                    color = TextSecondary,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 28.dp),
                )
            } else {
                if (filteredPopular.isNotEmpty()) {
                    Text(
                        text = "Most popular",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextSecondary,
                    )
                    Spacer(Modifier.height(12.dp))
                    // Non-lazy grid: this sits inside a verticalScroll Column, and a
                    // LazyVerticalGrid here is measured with infinite height, which
                    // throws at measure time (userScrollEnabled = false does not help).
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(22.dp),
                    ) {
                        filteredPopular.chunked(4).forEach { rowServices ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                rowServices.forEach { svc ->
                                    Box(modifier = Modifier.weight(1f)) {
                                        ServiceTile(
                                            service = svc,
                                            isSelected = svc.id in selected,
                                            onTap = { onToggle(svc.id) },
                                        )
                                    }
                                }
                                repeat(4 - rowServices.size) {
                                    Spacer(modifier = Modifier.weight(1f))
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(24.dp))
                }

                if (filteredAll.isNotEmpty()) {
                    Text(
                        text = "All services · A–Z",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextSecondary,
                    )
                    Spacer(Modifier.height(8.dp))
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color.White.copy(alpha = 0.04f))
                            .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp)),
                    ) {
                        filteredAll.forEachIndexed { idx, svc ->
                            ServiceToggleRow(
                                service = svc,
                                isSelected = svc.id in selected,
                                onTap = { onToggle(svc.id) },
                            )
                            if (idx < filteredAll.size - 1) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(1.dp)
                                        .background(Color.White.copy(alpha = 0.06f))
                                )
                            }
                        }
                    }
                    Spacer(Modifier.height(24.dp))
                }
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(SurfaceDark)
                .drawBehind {
                    drawRect(
                        color = Color.White.copy(alpha = 0.10f),
                        topLeft = Offset.Zero,
                        size = Size(width = size.width, height = 1f),
                    )
                }
                .padding(horizontal = 20.dp)
                .padding(top = 12.dp, bottom = 28.dp)
                .navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = "${selected.size} service${if (selected.size == 1) "" else "s"} selected",
                fontSize = 13.sp,
                color = TextSecondary,
            )
            Spacer(Modifier.height(14.dp))

            val ctaEnabled = selected.isNotEmpty()
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .clip(RoundedCornerShape(50.dp))
                    .background(
                        if (ctaEnabled) Brush.verticalGradient(
                            colors = listOf(BrandOrange, BrandOrange.copy(alpha = 0.85f)),
                        ) else SolidColor(Color.White.copy(alpha = 0.10f))
                    )
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        enabled = ctaEnabled,
                    ) { onContinue() },
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Build My Feed",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (ctaEnabled) Color.White else Color.White.copy(alpha = 0.35f),
                )
                Spacer(Modifier.width(8.dp))
                Icon(
                    imageVector = Icons.Filled.ArrowForward,
                    contentDescription = null,
                    tint = if (ctaEnabled) Color.White else Color.White.copy(alpha = 0.35f),
                    modifier = Modifier.size(16.dp),
                )
            }
            Spacer(Modifier.height(10.dp))
            Text(
                text = "Skip",
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = TextSecondary,
                modifier = Modifier
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onSkip() }
                    .padding(8.dp),
            )
        }
    }
}

@Composable
private fun ServiceMiniIcon(service: StreamingService, size: Dp) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(RoundedCornerShape(10.dp))
            .background(service.bg),
        contentAlignment = Alignment.Center,
    ) {
        val display = service.display
        val textSize = (size.value * 0.3f).sp
        when (display) {
            is StreamingService.Display.Text -> {
                Text(
                    text = display.text,
                    fontSize = textSize,
                    fontWeight = display.weight,
                    color = display.color,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                )
            }
            is StreamingService.Display.SymbolText -> {
                Text(
                    text = display.text,
                    fontSize = textSize,
                    fontWeight = FontWeight.Black,
                    color = display.color,
                )
            }
            is StreamingService.Display.Star -> {
                Text("\u2605", fontSize = (size.value * 0.5f).sp, color = display.color)
            }
        }
    }
}

@Composable
private fun ServiceToggleRow(
    service: StreamingService,
    isSelected: Boolean,
    onTap: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onTap() }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ServiceMiniIcon(service = service, size = 36.dp)
        Spacer(Modifier.width(12.dp))
        Text(
            text = service.name,
            fontSize = 15.sp,
            color = Color.White,
            modifier = Modifier.weight(1f),
        )
        VisualSwitch(checked = isSelected)
    }
}

@Composable
private fun VisualSwitch(checked: Boolean) {
    Box(
        modifier = Modifier
            .size(width = 44.dp, height = 26.dp)
            .clip(RoundedCornerShape(50.dp))
            .background(if (checked) BrandOrange else Color.White.copy(alpha = 0.15f)),
        contentAlignment = if (checked) Alignment.CenterEnd else Alignment.CenterStart,
    ) {
        Box(
            modifier = Modifier
                .padding(2.dp)
                .size(22.dp)
                .clip(CircleShape)
                .background(Color.White),
        )
    }
}

@Composable
private fun ServiceTile(
    service: StreamingService,
    isSelected: Boolean,
    onTap: () -> Unit,
) {
    val tileShape = RoundedCornerShape(13.dp)
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .graphicsLayer { alpha = if (isSelected) 1f else 0.52f },
        ) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .clip(tileShape)
                    .background(service.bg)
                    .then(
                        if (isSelected) Modifier.border(2.dp, Navy, tileShape)
                        else Modifier.border(1.dp, OutlineVariant, tileShape)
                    )
                    .then(
                        if (isSelected) Modifier.border(4.5.dp, Color.White, tileShape)
                        else Modifier
                    )
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onTap() },
                contentAlignment = Alignment.Center,
            ) {
                val display = service.display
                when (display) {
                    is StreamingService.Display.Text -> {
                        Text(
                            text = display.text,
                            fontSize = 11.sp,
                            fontWeight = display.weight,
                            color = display.color,
                            textAlign = TextAlign.Center,
                            maxLines = 2,
                            overflow = TextOverflow.Visible,
                        )
                    }
                    is StreamingService.Display.SymbolText -> {
                        Text(
                            text = display.text,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = display.color,
                            maxLines = 2,
                        )
                    }
                    is StreamingService.Display.Star -> {
                        Text("\u2605", fontSize = 20.sp, color = display.color)
                    }
                }
            }
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = 6.dp, y = (-6).dp)
                        .size(22.dp)
                        .clip(CircleShape)
                        .background(BrandOrange)
                        .border(2.dp, Navy, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Check,
                        contentDescription = "Selected",
                        tint = Color.White,
                        modifier = Modifier.size(13.dp),
                    )
                }
            }
        }
        Spacer(Modifier.height(4.dp))
        Text(
            text = service.name,
            fontSize = 9.sp,
            color = if (isSelected) Color.White else Color.White.copy(alpha = 0.35f),
            maxLines = 2,
            textAlign = TextAlign.Center,
            overflow = TextOverflow.Visible,
        )
    }
}

// ── Stay Notified (last step, redesigned) ─────────────────────────

@Composable
private fun StayNotifiedScreen(
    pushOn: Boolean,
    onPushToggle: (Boolean) -> Unit,
    onContinue: () -> Unit,
    onBack: () -> Unit,
    onWidgetSettings: () -> Unit,
    currentStep: Int,
    totalSteps: Int,
    posterUrls: List<String>,
    showCount: Int,
    creatorCount: Int,
) {
    val context = LocalContext.current
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            onPushToggle(true)
            PushTokenManager.get().registerIfPermitted()
        } else {
            onPushToggle(false)
        }
        onContinue()
    }

    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        OnboardingHeader(
            currentStep = currentStep,
            totalSteps = totalSteps,
            onBack = onBack,
        )

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (posterUrls.isNotEmpty()) {
                PosterStackHero(
                    posterUrls = posterUrls,
                    newCount = showCount,
                )
                Spacer(Modifier.height(20.dp))
            } else {
                Spacer(Modifier.height(24.dp))
            }

            Text(
                text = "Never miss an episode.",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = notifySubtitle(showCount, creatorCount),
                fontSize = 15.sp,
                color = TextSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 24.dp),
            )

            Spacer(Modifier.height(24.dp))

            // Benefit list
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(SurfaceContainer)
                    .border(1.dp, OutlineVariant, RoundedCornerShape(18.dp)),
            ) {
                for (i in 0 until 3) {
                    NotifyBenefitRow(
                        posterUrl = posterUrls.getOrNull(i),
                        title = benefitTitle(i),
                        subtitle = benefitSubtitle(i),
                    )
                    if (i < 2) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(1.dp)
                                .background(Color.White.copy(alpha = 0.06f))
                        )
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // Widget row (H2 — rewritten copy, no false promise)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(SurfaceContainer)
                    .border(1.dp, OutlineVariant, RoundedCornerShape(18.dp))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onWidgetSettings() }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(Color(red = 0.55f, green = 0.40f, blue = 0.95f).copy(alpha = 0.18f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.PhoneAndroid,
                        contentDescription = null,
                        tint = Color(red = 0.65f, green = 0.50f, blue = 1.0f),
                        modifier = Modifier.size(18.dp),
                    )
                }
                Spacer(Modifier.width(14.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Add the home screen widget",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextPrimary,
                    )
                    Text(
                        text = "Show tonight's episodes without opening the app",
                        fontSize = 12.sp,
                        color = TextSecondary,
                    )
                    Text(
                        text = "Takes about 15 seconds — we'll show you how",
                        fontSize = 11.sp,
                        color = TextTertiary,
                    )
                }
                Icon(
                    imageVector = Icons.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = TextSecondary,
                    modifier = Modifier.size(16.dp),
                )
            }

            Spacer(Modifier.height(90.dp))
        }

        // Buttons
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(SurfaceDark)
                .drawBehind {
                    drawRect(
                        color = Color.White.copy(alpha = 0.10f),
                        topLeft = Offset.Zero,
                        size = Size(width = size.width, height = 1f),
                    )
                }
                .padding(horizontal = 20.dp)
                .padding(top = 12.dp, bottom = 28.dp)
                .navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .clip(RoundedCornerShape(50.dp))
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(BrandOrange, BrandOrange.copy(alpha = 0.85f)),
                        ),
                    )
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        } else {
                            onPushToggle(true)
                            onContinue()
                        }
                    },
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Allow notifications",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
                Spacer(Modifier.width(8.dp))
                Icon(
                    imageVector = Icons.Filled.Notifications,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(16.dp),
                )
            }
            Spacer(Modifier.height(12.dp))
            Text(
                text = "Not now",
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = TextSecondary,
                modifier = Modifier
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        onPushToggle(false)
                        onContinue()
                    }
                    .padding(8.dp),
            )
        }
    }
}

private fun notifySubtitle(showCount: Int, creatorCount: Int): String {
    val parts = mutableListOf<String>()
    if (showCount > 0) parts.add("$showCount show${if (showCount == 1) "" else "s"}")
    if (creatorCount > 0) parts.add("$creatorCount creator${if (creatorCount == 1) "" else "s"}")
    return if (parts.isEmpty()) {
        "Turn on alerts so you never miss a new episode."
    } else {
        "You're following ${parts.joinToString(" and ")}. Turn on alerts so you never miss a new episode."
    }
}

private fun benefitTitle(i: Int): String = when (i) {
    0 -> "New episode alerts"
    1 -> "Watch list updates"
    else -> "Deep links"
}

private fun benefitSubtitle(i: Int): String = when (i) {
    0 -> "Know the moment a new episode drops"
    1 -> "See when your shows have new content"
    else -> "One tap straight to the episode"
}

@Composable
private fun PosterStackHero(
    posterUrls: List<String>,
    newCount: Int,
) {
    Box(
        modifier = Modifier.height(130.dp),
        contentAlignment = Alignment.Center,
    ) {
        val display = posterUrls.take(5)
        val count = display.size
        display.forEachIndexed { i, url ->
            val mid = (count - 1) / 2.0f
            val angle = ((i - mid) * 7.0f)
            val xOffset = ((i - mid) * 16f).dp
            RemoteImage(
                url = url,
                contentDescription = null,
                modifier = Modifier
                    .size(width = 76.dp, height = 114.dp)
                    .graphicsLayer {
                        rotationZ = angle
                        translationX = xOffset.toPx()
                    }
                    .clip(RoundedCornerShape(8.dp))
                    .border(0.5.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(8.dp)),
            )
        }
        // H5 — small bell mark instead of fabricated count
        Icon(
            imageVector = Icons.Filled.Notifications,
            contentDescription = null,
            tint = BrandOrange,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .offset(x = 20.dp, y = (-10).dp)
                .size(16.dp),
        )
    }
}

@Composable
private fun NotifyBenefitRow(
    posterUrl: String?,
    title: String,
    subtitle: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (posterUrl != null) {
            RemoteImage(
                url = posterUrl,
                contentDescription = null,
                modifier = Modifier
                    .size(width = 36.dp, height = 54.dp)
                    .clip(RoundedCornerShape(6.dp)),
            )
        } else {
            // H4 — quiet monochrome glyph, not a brown placeholder
            Box(
                modifier = Modifier
                    .size(width = 36.dp, height = 54.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color.White.copy(alpha = 0.06f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (title == "New episode alerts") Icons.Filled.PlayArrow
                        else if (title == "Watch list updates") Icons.Filled.Check
                        else Icons.Filled.ArrowForward,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.25f),
                    modifier = Modifier.size(16.dp),
                )
            }
        }
        Spacer(Modifier.width(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
            )
            Text(
                text = subtitle,
                fontSize = 12.sp,
                color = TextSecondary,
            )
        }
    }
}

// ── Onboarding header + step indicator ─────────────────────────────

internal object OnboardingHeader {
    val stepNames = listOf("Services", "Watching", "Creators", "Notify")
}

@Composable
internal fun OnboardingHeader(
    currentStep: Int,
    totalSteps: Int,
    onBack: (() -> Unit)? = null,
    onSkipAll: (() -> Unit)? = null,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(SurfaceContainer)
            .statusBarsPadding(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 4.dp, bottom = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null && currentStep > 1) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.10f))
                        .clickable { onBack() },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.KeyboardArrowLeft,
                        contentDescription = "Back",
                        tint = Color.White,
                        modifier = Modifier.size(20.dp),
                    )
                }
            } else {
                Spacer(Modifier.size(36.dp))
            }
            Spacer(Modifier.weight(1f))
            BrandWordmark(size = com.rork.guidestreamtvandroid.ui.theme.WordmarkSize.NAV)
            Spacer(Modifier.weight(1f))
            if (onSkipAll != null) {
                Text(
                    text = "Skip all",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = TextSecondary,
                    modifier = Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onSkipAll() }
                        .padding(4.dp),
                )
            } else {
                Spacer(Modifier.size(36.dp))
            }
        }

        OnboardingStepIndicator(
            currentStep = currentStep,
            totalSteps = totalSteps,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(top = 4.dp, bottom = 8.dp),
        )
    }
}

@Composable
private fun OnboardingStepIndicator(
    currentStep: Int,
    totalSteps: Int,
    modifier: Modifier = Modifier,
) {
    val nodeSize = 26.dp
    val ringSize = 34.dp

    Column(modifier = modifier) {
        // Indicator row
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for (i in 0 until totalSteps) {
                val stepNum = i + 1
                if (i > 0) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(1.5.dp)
                            .background(
                                if (i < currentStep) BrandBlue.copy(alpha = 0.75f)
                                else Color.White.copy(alpha = 0.15f)
                            )
                    )
                }
                StepNode(
                    stepNum = stepNum,
                    isCompleted = stepNum < currentStep,
                    isCurrent = stepNum == currentStep,
                    isUpcoming = stepNum > currentStep,
                    nodeSize = nodeSize,
                    ringSize = ringSize,
                )
            }
        }
        // Labels
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
        ) {
            for (i in 0 until totalSteps) {
                if (i > 0) {
                    Spacer(Modifier.weight(1f))
                }
                Text(
                    text = OnboardingHeader.stepNames[i],
                    fontSize = 10.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 1.sp,
                    color = Color.White.copy(alpha = 0.35f),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun StepNode(
    stepNum: Int,
    isCompleted: Boolean,
    isCurrent: Boolean,
    isUpcoming: Boolean,
    nodeSize: Dp,
    ringSize: Dp,
) {
    Box(
        modifier = Modifier.size(ringSize),
        contentAlignment = Alignment.Center,
    ) {
        if (isCurrent) {
            Canvas(modifier = Modifier.size(ringSize)) {
                val strokePx = 2.5.dp.toPx()
                drawCircle(
                    color = Color.White.copy(alpha = 0.14f),
                    style = Stroke(width = strokePx),
                )
                drawArc(
                    color = BrandOrange,
                    startAngle = -90f,
                    sweepAngle = 360f,
                    useCenter = false,
                    style = Stroke(width = strokePx, cap = StrokeCap.Round),
                )
            }
        }

        Box(
            modifier = Modifier
                .size(nodeSize)
                .clip(CircleShape)
                .background(
                    when {
                        isCompleted -> BrandBlue.copy(alpha = 0.9f)
                        isCurrent -> BrandOrange
                        else -> Color.Transparent
                    }
                )
                .then(
                    if (isUpcoming) {
                        Modifier.border(1.5.dp, Color.White.copy(alpha = 0.18f), CircleShape)
                    } else {
                        Modifier
                    }
                ),
            contentAlignment = Alignment.Center,
        ) {
            if (isCompleted) {
                Icon(
                    imageVector = Icons.Filled.Check,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(12.dp),
                )
            } else {
                Text(
                    text = "$stepNum",
                    fontSize = 12.sp,
                    fontWeight = if (isCurrent) FontWeight.Bold else FontWeight.SemiBold,
                    color = if (isCurrent) Color.White else Color.White.copy(alpha = 0.35f),
                )
            }
        }
    }
}

// ── Widget Instruction Sheet (H3) ─────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WidgetInstructionSheet(onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = SheetSurfaceBase,
        scrimColor = Color.Black.copy(alpha = 0.60f),
        tonalElevation = 0.dp,
        dragHandle = { GsSheetDragHandle(level = SheetLevel.Base) },
        contentWindowInsets = { sheetTopInset() },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding(),
        ) {
            GsSheetHeader(title = "Add the home screen widget") {
                Text(
                    text = "Done",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    color = TextSecondary,
                    modifier = Modifier.clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onDismiss() }.padding(4.dp),
                )
            }

            // Widget preview card
            WidgetPreviewCard(Modifier.padding(horizontal = 20.dp).padding(top = 8.dp))

            Spacer(Modifier.height(18.dp))

            // Numbered steps (Android-specific)
            WidgetStepRow(number = 1, text = "Touch and hold an empty area of your home screen", modifier = Modifier.padding(horizontal = 20.dp))
            Spacer(Modifier.height(14.dp))
            WidgetStepRow(number = 2, text = "Tap Widgets", modifier = Modifier.padding(horizontal = 20.dp))
            Spacer(Modifier.height(14.dp))
            WidgetStepRow(number = 3, text = "Find GuideStream TV and drag your preferred size into place", modifier = Modifier.padding(horizontal = 20.dp))

            Spacer(Modifier.height(24.dp))

            // Buttons
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(48.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color.White.copy(alpha = 0.06f))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onDismiss() },
                    contentAlignment = Alignment.Center,
                ) {
                    Text("Remind me later", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = TextSecondary)
                }
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(48.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(Brush.verticalGradient(listOf(BrandOrange, BrandOrange.copy(alpha = 0.85f))))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onDismiss() },
                    contentAlignment = Alignment.Center,
                ) {
                    Text("Got it", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White)
                }
            }
        }
    }
}

@Composable
private fun WidgetStepRow(number: Int, text: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(BrandOrange.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            Text("$number", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = BrandOrange)
        }
        Spacer(Modifier.width(14.dp))
        Text(
            text = text,
            fontSize = 15.sp,
            color = TextPrimary,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun WidgetPreviewCard(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(SurfaceDark)
            .border(1.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(16.dp))
            .padding(14.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("GuideStream", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
            Text("TONIGHT", fontSize = 9.sp, fontWeight = FontWeight.Bold, color = BrandOrange, letterSpacing = 1.sp)
        }
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(modifier = Modifier.size(width = 24.dp, height = 36.dp).clip(RoundedCornerShape(4.dp)).background(BrandBlue.copy(alpha = 0.6f)))
            Spacer(Modifier.width(8.dp))
            Text("New episode \u00b7 The Last of Us", fontSize = 11.sp, color = TextSecondary)
        }
        Spacer(Modifier.height(4.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(modifier = Modifier.size(width = 24.dp, height = 36.dp).clip(RoundedCornerShape(4.dp)).background(BrandOrange.copy(alpha = 0.6f)))
            Spacer(Modifier.width(8.dp))
            Text("Season finale \u00b7 Severance", fontSize = 11.sp, color = TextSecondary)
        }
    }
}
