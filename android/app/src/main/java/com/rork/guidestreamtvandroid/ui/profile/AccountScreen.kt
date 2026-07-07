package com.rork.guidestreamtvandroid.ui.profile

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.SupabaseConfig
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import io.github.jan.supabase.auth.auth
import io.ktor.client.HttpClient
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.isSuccess
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Account screen — mirrors iOS AccountView.swift.
 * Avatar, display name editor, info card (email, sign-in method, user ID),
 * reset password, delete account (calls delete_account edge function).
 */
@Composable
fun AccountScreen(
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val authVm = AuthViewModel.get()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val currentUser by authVm.currentUser.collectAsStateWithLifecycle()
    val displayName by authVm.displayName.collectAsStateWithLifecycle()
    val firstName by authVm.firstName.collectAsStateWithLifecycle()
    val lastName by authVm.lastName.collectAsStateWithLifecycle()
    val isAuthenticated by authVm.isAuthenticated.collectAsStateWithLifecycle()

    var nameDraft by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var savedFlash by remember { mutableStateOf(false) }
    var isDeleting by remember { mutableStateOf(false) }
    var deleteError by remember { mutableStateOf<String?>(null) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var isSendingReset by remember { mutableStateOf(false) }
    var showResetSent by remember { mutableStateOf(false) }

    LaunchedEffect(displayName) {
        if (nameDraft.isEmpty() && displayName != null) {
            nameDraft = displayName!!
        }
    }

    val initials = remember(firstName, lastName, displayName) {
        val f = firstName?.trim()?.firstOrNull()?.uppercaseChar()
        val l = lastName?.trim()?.firstOrNull()?.uppercaseChar()
        if (f != null && l != null) "$f$l" else (f ?: displayName?.firstOrNull()?.uppercaseChar() ?: "?").toString()
    }

    Box(modifier = modifier.fillMaxSize().background(Color(red = 0x04, green = 0x09, blue = 0x0F))) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp),
        ) {
            Spacer(Modifier.height(48.dp))

            // Back button
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
            Text("Account", fontSize = 24.sp, fontWeight = FontWeight.Black, color = TextPrimary)
            Spacer(Modifier.height(20.dp))

            if (!isAuthenticated) {
                // Guest prompt
                Text("You're browsing as a guest.", fontSize = 16.sp, color = TextSecondary)
                Spacer(Modifier.height(8.dp))
                Text("Sign in with email or Google to sync your shows, devices, and watch history.", fontSize = 13.sp, color = TextTertiary)
                Spacer(Modifier.height(40.dp))
                return@Column
            }

            // Avatar header
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(
                    modifier = Modifier
                        .size(80.dp)
                        .clip(CircleShape)
                        .background(BrandOrange.copy(alpha = 0.2f))
                        .border(2.dp, BrandOrange, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(initials, fontSize = 28.sp, fontWeight = FontWeight.Black, color = BrandOrange)
                }
                Spacer(Modifier.height(10.dp))
                Text(displayName ?: "Account", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                if (currentUser?.email != null) {
                    Text(currentUser!!.email!!, fontSize = 12.sp, color = TextSecondary)
                }
            }

            Spacer(Modifier.height(20.dp))

            // Name editor
            Text("DISPLAY NAME", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = TextTertiary)
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                BasicTextField(
                    value = nameDraft,
                    onValueChange = { nameDraft = it },
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(12.dp))
                        .background(GlassFill)
                        .border(1.dp, GlassStroke, RoundedCornerShape(12.dp))
                        .padding(horizontal = 14.dp, vertical = 14.dp),
                    textStyle = TextStyle(color = TextPrimary, fontSize = 16.sp),
                    cursorBrush = SolidColor(BrandOrange),
                    singleLine = true,
                )
                Spacer(Modifier.width(10.dp))
                val saveDisabled = nameDraft.trim().isEmpty() || nameDraft.trim() == displayName || isSaving
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(12.dp))
                        .background(if (saveDisabled) BrandOrange.copy(alpha = 0.35f) else BrandOrange)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) {
                            if (!saveDisabled) {
                                scope.launch {
                                    isSaving = true
                                    val ok = authVm.updateDisplayName(nameDraft.trim())
                                    isSaving = false
                                    if (ok) {
                                        savedFlash = true
                                        kotlinx.coroutines.delay(1600)
                                        savedFlash = false
                                    }
                                }
                            }
                        }
                        .padding(horizontal = 18.dp, vertical = 14.dp),
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(color = Color.White, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    } else {
                        Text("Save", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }
            }

            if (savedFlash) {
                Spacer(Modifier.height(8.dp))
                Text("✓ Saved", fontSize = 13.sp, color = Color(0xFF00CE6A))
            }

            Spacer(Modifier.height(20.dp))

            // Info card
            InfoRow("Email", currentUser?.email ?: "—")
            Spacer(Modifier.height(6.dp))
            InfoRow("User ID", currentUser?.id?.take(10) ?: "—")
            Spacer(Modifier.height(20.dp))

            // Reset password
            ActionRow(
                title = "Reset password",
                subtitle = if (isSendingReset) "Sending…" else "We'll email you a recovery link",
                onClick = {
                    val email = currentUser?.email ?: return@ActionRow
                    scope.launch {
                        isSendingReset = true
                        authVm.sendPasswordReset(email)
                        isSendingReset = false
                        showResetSent = true
                    }
                },
            )

            Spacer(Modifier.height(20.dp))

            // Delete account
            ActionRow(
                title = "Delete account",
                subtitle = "Permanently remove your data",
                titleColor = Color(0xFFE55050),
                onClick = { showDeleteConfirm = true },
            )

            if (deleteError != null) {
                Spacer(Modifier.height(8.dp))
                Text("⚠ $deleteError", fontSize = 13.sp, color = Color(0xFFE55050))
            }

            Spacer(Modifier.height(60.dp))
        }

        // Delete confirmation dialog
        if (showDeleteConfirm) {
            DeleteConfirmDialog(
                isDeleting = isDeleting,
                onConfirm = {
                    scope.launch {
                        isDeleting = true
                        deleteError = null
                        try {
                            val ok = deleteAccount()
                            if (ok) {
                                authVm.signOut()
                                onClose()
                            } else {
                                deleteError = "Couldn't delete your account. Check your connection and try again."
                            }
                        } catch (_: Exception) {
                            deleteError = "Couldn't delete your account. Check your connection and try again."
                        } finally {
                            isDeleting = false
                        }
                    }
                },
                onDismiss = { showDeleteConfirm = false },
            )
        }

        // Reset sent dialog
        if (showResetSent) {
            SimpleDialog(
                title = "Reset link sent",
                message = "Check your inbox for a recovery link to set a new password.",
                onDismiss = { showResetSent = false },
            )
        }
    }
}

private suspend fun deleteAccount(): Boolean = withContext(Dispatchers.IO) {
    try {
        val session = SupabaseManager.client.auth.currentSessionOrNull()
        val accessToken = session?.accessToken ?: return@withContext false
        val url = "${SupabaseConfig.URL}/functions/v1/delete_account"
        val client = HttpClient()
        val response: HttpResponse = client.post(url) {
            headers.append(HttpHeaders.ContentType, ContentType.Application.Json.toString())
            headers.append("apikey", SupabaseConfig.ANON_KEY)
            headers.append(HttpHeaders.Authorization, "Bearer $accessToken")
            setBody("{}")
        }
        client.close()
        response.status.isSuccess()
    } catch (_: Exception) {
        false
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().glassCard(10).padding(12.dp),
    ) {
        Text(label, fontSize = 13.sp, color = TextSecondary, modifier = Modifier.width(90.dp))
        Text(value, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
    }
}

@Composable
private fun ActionRow(
    title: String,
    subtitle: String,
    titleColor: Color = TextPrimary,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(10)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = titleColor)
            Text(subtitle, fontSize = 12.sp, color = TextTertiary)
        }
    }
}

@Composable
private fun DeleteConfirmDialog(
    isDeleting: Boolean,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    Box(
        modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.7f)).clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
        ) { onDismiss() },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 32.dp).glassCard(16).padding(24.dp),
        ) {
            Text("Delete account?", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
            Spacer(Modifier.height(8.dp))
            Text(
                "Your account will be permanently deleted. You'll be signed out immediately and lose access to your saved shows, devices, and history.",
                fontSize = 14.sp, color = TextSecondary,
            )
            Spacer(Modifier.height(20.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(
                    modifier = Modifier.weight(1f).clip(RoundedCornerShape(12.dp))
                        .background(GlassFill).border(1.dp, GlassStroke, RoundedCornerShape(12.dp))
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onDismiss() }
                        .padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) { Text("Cancel", fontSize = 14.sp, color = TextPrimary) }
                Box(
                    modifier = Modifier.weight(1f).clip(RoundedCornerShape(12.dp))
                        .background(Color(0xFFE55050))
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { if (!isDeleting) onConfirm() }
                        .padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    if (isDeleting) {
                        CircularProgressIndicator(color = Color.White, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    } else {
                        Text("Delete", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }
            }
        }
    }
}

@Composable
private fun SimpleDialog(title: String, message: String, onDismiss: () -> Unit) {
    Box(
        modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.7f)).clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
        ) { onDismiss() },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 32.dp).glassCard(16).padding(24.dp),
        ) {
            Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
            Spacer(Modifier.height(8.dp))
            Text(message, fontSize = 14.sp, color = TextSecondary)
            Spacer(Modifier.height(16.dp))
            Box(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                    .background(BrandOrange)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onDismiss() }
                    .padding(vertical = 12.dp),
                contentAlignment = Alignment.Center,
            ) { Text("OK", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White) }
        }
    }
}
