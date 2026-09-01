package com.rork.guidestreamtvandroid.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.BuildConfig
import com.rork.guidestreamtvandroid.data.remote.SupportRequestService
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import kotlinx.coroutines.launch

/** The topic vocabulary the website support form already uses. */
val SupportTopics = listOf(
    "Something is broken",
    "I have a question",
    "Feature request",
    "Account or billing",
)

/**
 * In-app support form (GUI-87).
 *
 * Replaces the mailto: hand-off. The customer writes to us without leaving
 * GuideStream, and the app version, build, device model, OS version and
 * device id ride along automatically instead of being pasted into an email
 * body that people routinely deleted.
 */
@Composable
fun SupportFormScreen(
    presetTopic: String,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val authVm = AuthViewModel.get()
    val scope = rememberCoroutineScope()
    val currentUser by authVm.currentUser.collectAsStateWithLifecycle()
    val displayName by authVm.displayName.collectAsStateWithLifecycle()

    var topic by remember { mutableStateOf(presetTopic) }
    var email by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var sent by remember { mutableStateOf(false) }

    // Prefill from the signed-in account. Guests type their own address.
    LaunchedEffect(currentUser) {
        if (email.isEmpty()) email = currentUser?.email.orEmpty()
    }

    val emailValid = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(email.trim())
    val canSend = !isSending && emailValid && message.trim().isNotEmpty()

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Color(red = 0x04, green = 0x09, blue = 0x0F))
            .verticalScroll(rememberScrollState())
            .imePadding()
            .padding(horizontal = 20.dp),
    ) {
        Spacer(Modifier.height(48.dp))
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(GlassFill)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onClose() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.ArrowBack, "Back", tint = TextPrimary, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.height(16.dp))

        if (sent) {
            Text("Message sent", fontSize = 24.sp, fontWeight = FontWeight.Black, color = TextPrimary)
            Spacer(Modifier.height(10.dp))
            Row(
                modifier = Modifier.fillMaxWidth().glassCard(10).padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Check, null, tint = BrandOrange, modifier = Modifier.size(22.dp))
                Column(Modifier.padding(start = 12.dp)) {
                    Text(
                        "Thanks — we've got it.",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextPrimary,
                    )
                    Text(
                        "We'll reply to ${email.trim()}.",
                        fontSize = 13.sp,
                        color = TextSecondary,
                    )
                }
            }
            Spacer(Modifier.height(20.dp))
            PrimaryButton("Done", enabled = true) { onClose() }
            Spacer(Modifier.height(40.dp))
            return@Column
        }

        Text("Contact Support", fontSize = 24.sp, fontWeight = FontWeight.Black, color = TextPrimary)
        Spacer(Modifier.height(6.dp))
        Text(
            "Tell us what's going on and we'll get back to you by email.",
            fontSize = 13.sp,
            color = TextSecondary,
        )
        Spacer(Modifier.height(20.dp))

        Text("TOPIC", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = TextTertiary)
        Spacer(Modifier.height(8.dp))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SupportTopics.forEach { option ->
                val selected = option == topic
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(20.dp))
                        .background(if (selected) BrandOrange else GlassFill)
                        .border(
                            1.dp,
                            if (selected) BrandOrange else GlassStroke,
                            RoundedCornerShape(20.dp),
                        )
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { topic = option }
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                ) {
                    Text(
                        option,
                        fontSize = 13.sp,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (selected) Color.White else TextSecondary,
                    )
                }
            }
        }

        Spacer(Modifier.height(20.dp))
        Text("YOUR EMAIL", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = TextTertiary)
        Spacer(Modifier.height(6.dp))
        BasicTextField(
            value = email,
            onValueChange = { email = it; error = null },
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(GlassFill)
                .border(1.dp, GlassStroke, RoundedCornerShape(12.dp))
                .padding(horizontal = 14.dp, vertical = 14.dp),
            textStyle = TextStyle(color = TextPrimary, fontSize = 16.sp),
            cursorBrush = SolidColor(BrandOrange),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            decorationBox = { inner ->
                Box {
                    if (email.isEmpty()) {
                        Text("you@example.com", fontSize = 16.sp, color = TextTertiary)
                    }
                    inner()
                }
            },
        )

        Spacer(Modifier.height(16.dp))
        Text("MESSAGE", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = TextTertiary)
        Spacer(Modifier.height(6.dp))
        BasicTextField(
            value = message,
            onValueChange = { if (it.length <= 4000) { message = it; error = null } },
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 160.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(GlassFill)
                .border(1.dp, GlassStroke, RoundedCornerShape(12.dp))
                .padding(horizontal = 14.dp, vertical = 14.dp),
            textStyle = TextStyle(color = TextPrimary, fontSize = 15.sp),
            cursorBrush = SolidColor(BrandOrange),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            decorationBox = { inner ->
                Box {
                    if (message.isEmpty()) {
                        Text(
                            "What happened, and what were you doing at the time?",
                            fontSize = 15.sp,
                            color = TextTertiary,
                        )
                    }
                    inner()
                }
            },
        )

        Spacer(Modifier.height(12.dp))
        Text(
            "We'll include your app version (${BuildConfig.VERSION_NAME}), device and " +
                "device ID so we can find the problem faster.",
            fontSize = 11.sp,
            color = TextTertiary,
        )

        if (error != null) {
            Spacer(Modifier.height(10.dp))
            Text(error!!, fontSize = 13.sp, color = Color(0xFFFF6B6B))
        }

        Spacer(Modifier.height(18.dp))
        PrimaryButton(if (isSending) "Sending…" else "Send", enabled = canSend) {
            scope.launch {
                isSending = true
                error = null
                val ok = SupportRequestService.submit(
                    name = displayName.orEmpty(),
                    email = email.trim(),
                    topic = topic,
                    message = message.trim(),
                )
                isSending = false
                if (ok) sent = true else error = "Couldn't send that. Check your connection and try again."
            }
        }
        if (isSending) {
            Spacer(Modifier.height(12.dp))
            CircularProgressIndicator(color = BrandOrange, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.height(60.dp))
    }
}

@Composable
private fun PrimaryButton(label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(if (enabled) BrandOrange else BrandOrange.copy(alpha = 0.35f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { if (enabled) onClick() }
            .padding(vertical = 15.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White)
    }
}
