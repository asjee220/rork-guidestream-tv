package com.rork.guidestreamtvandroid.ui.onboarding

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Email
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.ui.theme.BrandBackground
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.BrandWordmark
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import kotlinx.coroutines.launch

/**
 * Onboarding flow — mirrors iOS OnboardingFlow.swift.
 * Welcome → Connect Services → Stay Notified.
 */
@Composable
fun OnboardingFlow(
    startStep: Int = 0,
    onFinish: () -> Unit,
) {
    var step by remember { mutableStateOf(startStep) }
    var showEmailAuth by remember { mutableStateOf(false) }
    val auth = AuthViewModel.get()
    val streams = StreamsViewModel.get()
    val selectedServices = remember { mutableStateOf(auth.selectedServices.value) }
    var pushOn by remember { mutableStateOf(auth.notifyPushEnabled.value) }
    val scope = rememberCoroutineScope()

    // Terminal path: mark onboarding complete and hand control back to the host.
    val finish: () -> Unit = {
        if (!auth.isAuthenticated.value) auth.continueAsGuest()
        auth.completeOnboarding()
        onFinish()
    }

    // Commit seeded shows / creators into the watchlist (guest or signed-in).
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
                )
                2 -> StayNotifiedScreen(
                    pushOn = pushOn,
                    onPushToggle = { pushOn = it },
                    onContinue = {
                        auth.setNotificationPreferences(pushOn, false)
                        if (!auth.isAuthenticated.value) auth.continueAsGuest()
                        step = 3
                    },
                )
                3 -> SeedPromptScreen(
                    selectedServices = selectedServices.value,
                    onContinue = { step = 4 },
                    onSkip = { finish() },
                )
                4 -> WatchingNowScreen(
                    selectedServices = selectedServices.value,
                    onContinue = { seeds ->
                        commitSeeds(seeds)
                        step = 5
                    },
                    onSkip = { step = 5 },
                )
                else -> FollowCreatorsOnboardingScreen(
                    onContinue = { seeds ->
                        commitSeeds(seeds)
                        finish()
                    },
                    onSkip = { finish() },
                )
            }
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
                        step = 1
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
) {
    val auth = AuthViewModel.get()
    val isAuthenticating by auth.isAuthenticating.collectAsState()
    val lastError by auth.lastError.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp)
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(80.dp))

        // Logo
        BrandWordmark(size = com.rork.guidestreamtvandroid.ui.theme.WordmarkSize.LARGE)
        Spacer(Modifier.height(8.dp))

        // Gradient hairline underline
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

        // Card with copy + auth options
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
                fontSize = 15.sp,
                color = TextSecondary,
            )
            Text(
                text = "What are you watching now?",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Spacer(Modifier.height(16.dp))

            // Sign in with Google — full width
            AuthButton(
                text = "Sign in with Google",
                background = Color.White,
                textColor = Color(red = 0.24f, green = 0.25f, blue = 0.26f),
                isLoading = isAuthenticating,
                onClick = { auth.signInWithGoogle { success -> if (success) onContinue() } },
            )
            Spacer(Modifier.height(12.dp))

            // Divider — "or"
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(1.dp)
                        .background(Color.White.copy(alpha = 0.1f)),
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
                        .background(Color.White.copy(alpha = 0.1f)),
                )
            }
            Spacer(Modifier.height(12.dp))

            // Sign in with email — outlined
            OutlinedAuthButton(
                text = "Sign in with email",
                icon = Icons.Filled.Email,
                onClick = onEmailAuth,
            )

            if (lastError != null) {
                Spacer(Modifier.height(12.dp))
                Text(
                    text = lastError ?: "",
                    fontSize = 11.sp,
                    color = Color.Red.copy(alpha = 0.85f),
                    textAlign = TextAlign.Center,
                )
            }

            Spacer(Modifier.height(12.dp))
            Text(
                text = "By continuing, you agree to our Privacy Policy and Terms of Service.",
                fontSize = 11.sp,
                color = TextTertiary,
                textAlign = TextAlign.Center,
            )
        }
    }
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

// ── Connect Services ──────────────────────────────────────────────

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ConnectServicesScreen(
    selected: Set<String>,
    onToggle: (String) -> Unit,
    onContinue: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize(),
    ) {
        OnboardingHeader(progress = 1f, onClose = null)

        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            items(StreamingCatalog.all, key = { it.id }) { svc ->
                ServiceTile(
                    service = svc,
                    isSelected = svc.id in selected,
                    onTap = { onToggle(svc.id) },
                )
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = "${selected.size} service${if (selected.size == 1) "" else "s"} selected",
                fontSize = 13.sp,
                color = TextSecondary,
            )
            Spacer(Modifier.height(14.dp))

            // Continue button
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
                        enabled = selected.isNotEmpty(),
                    ) { onContinue() },
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Build My Feed",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
                Spacer(Modifier.width(8.dp))
                Icon(
                    imageVector = Icons.Filled.ArrowForward,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}

@Composable
private fun ServiceTile(
    service: com.rork.guidestreamtvandroid.data.models.StreamingService,
    isSelected: Boolean,
    onTap: () -> Unit,
) {
    val borderColor = if (isSelected) service.glow else Color.White.copy(alpha = 0.08f)
    val borderWidth = if (isSelected) 2.dp else 1.dp
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(0.75f)
            .clip(RoundedCornerShape(14.dp))
            .background(service.bg)
            .border(borderWidth, borderColor, RoundedCornerShape(14.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onTap() },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        val display = service.display
        when (display) {
            is com.rork.guidestreamtvandroid.data.models.StreamingService.Display.Text -> {
                Text(
                    text = display.text,
                    fontSize = 13.sp,
                    fontWeight = display.weight,
                    color = display.color,
                    textAlign = TextAlign.Center,
                )
            }
            is com.rork.guidestreamtvandroid.data.models.StreamingService.Display.SymbolText -> {
                Text(
                    text = display.text,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = display.color,
                )
            }
            is com.rork.guidestreamtvandroid.data.models.StreamingService.Display.Star -> {
                Text("\u2605", fontSize = 24.sp, color = display.color)
            }
        }
        Spacer(Modifier.height(4.dp))
        Text(
            text = service.name,
            fontSize = 9.sp,
            color = Color.White.copy(alpha = 0.5f),
            maxLines = 1,
        )
    }
}

// ── Stay Notified ─────────────────────────────────────────────────

@Composable
private fun StayNotifiedScreen(
    pushOn: Boolean,
    onPushToggle: (Boolean) -> Unit,
    onContinue: () -> Unit,
) {
    val context = LocalContext.current
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            onPushToggle(true)
        } else {
            onPushToggle(false)
        }
    }

    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        OnboardingHeader(progress = 1f, onClose = null)

        Spacer(Modifier.height(24.dp))

        // Bell hero
        Box(
            modifier = Modifier.size(220.dp),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(220.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.04f)),
            )
            Box(
                modifier = Modifier
                    .size(92.dp)
                    .clip(CircleShape)
                    .background(
                        Brush.linearGradient(
                            colors = listOf(
                                Color(red = 0.36f, green = 0.42f, blue = 0.96f),
                                Color(red = 0.62f, green = 0.40f, blue = 0.95f),
                            ),
                        ),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Notifications,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(38.dp),
                )
            }
        }

        Spacer(Modifier.height(16.dp))
        Text(
            text = "Never miss an episode.",
            fontSize = 30.sp,
            fontWeight = FontWeight.Bold,
            color = TextPrimary,
        )
        Text(
            text = "Stay updated with your favorite shows",
            fontSize = 15.sp,
            color = TextSecondary,
        )

        Spacer(Modifier.height(24.dp))

        // Notification options card
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(Color.White.copy(alpha = 0.04f))
                .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(18.dp)),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(BrandOrange.copy(alpha = 0.18f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Notifications,
                        contentDescription = null,
                        tint = BrandOrange,
                        modifier = Modifier.size(18.dp),
                    )
                }
                Spacer(Modifier.width(14.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "New episode alerts",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextPrimary,
                    )
                    Text(
                        text = "Push notification",
                        fontSize = 12.sp,
                        color = TextSecondary,
                    )
                }
                Switch(
                    checked = pushOn,
                    onCheckedChange = { value ->
                        if (value && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        } else {
                            onPushToggle(value)
                        }
                    },
                    colors = SwitchDefaults.colors(
                        checkedTrackColor = BrandOrange,
                    ),
                )
            }
        }

        Spacer(Modifier.weight(1f))

        // Continue button
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp)
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
                ) { onContinue() },
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "I'm all set",
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
            Spacer(Modifier.width(8.dp))
            Icon(
                imageVector = Icons.Filled.ArrowForward,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

// ── Onboarding header ─────────────────────────────────────────────

@Composable
internal fun OnboardingHeader(
    progress: Float,
    onClose: (() -> Unit)? = null,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = 0.04f)),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 4.dp, bottom = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onClose != null) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.10f))
                        .clickable { onClose() },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "Close",
                        tint = Color.White,
                        modifier = Modifier.size(14.dp),
                    )
                }
            } else {
                Spacer(Modifier.size(36.dp))
            }
            Spacer(Modifier.weight(1f))
            BrandWordmark(size = com.rork.guidestreamtvandroid.ui.theme.WordmarkSize.NAV)
            Spacer(Modifier.weight(1f))
            Spacer(Modifier.size(36.dp))
        }
        // Split progress bar — blue (done) + orange (current)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(top = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(3.dp)
                    .clip(RoundedCornerShape(50.dp))
                    .background(
                        Brush.horizontalGradient(
                            colors = listOf(BrandBlue.copy(alpha = 0.6f), BrandBlue),
                        ),
                    ),
            )
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(3.dp)
                    .clip(RoundedCornerShape(50.dp))
                    .background(
                        if (progress >= 1f) {
                            Brush.horizontalGradient(
                                colors = listOf(BrandOrange.copy(alpha = 0.6f), BrandOrange),
                            )
                        } else {
                            Brush.horizontalGradient(
                                colors = listOf(Color.White.copy(alpha = 0.12f), Color.White.copy(alpha = 0.12f)),
                            )
                        },
                    ),
            )
        }
    }
}
