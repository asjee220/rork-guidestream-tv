package com.rork.guidestreamtvandroid.ui.onboarding

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.ui.theme.BrandBackground
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Hairline
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.SurfaceContainer
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import kotlinx.coroutines.launch

/**
 * Set-new-password screen — mirrors iOS UpdatePasswordView.swift. Presented
 * over the current content when a Supabase recovery callback imports a
 * session. Reuses the field + button styling from [EmailAuthScreen] so the
 * experience matches the rest of the email auth flow.
 */
@Composable
fun UpdatePasswordScreen(
    onDismiss: () -> Unit,
) {
    val auth = AuthViewModel.get()
    val scope = rememberCoroutineScope()
    val isAuthenticating by auth.isAuthenticating.collectAsState()
    val lastError by auth.lastError.collectAsState()
    val lastInfo by auth.lastInfo.collectAsState()

    var newPassword by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }

    val canSubmit = newPassword.length >= 8 && newPassword == confirmPassword

    LaunchedEffect(Unit) {
        // Clear stale messages from a prior auth flow so the recovery
        // screen starts clean.
        auth.lastError
        auth.lastInfo
    }

    Box(modifier = Modifier.fillMaxSize()) {
        BrandBackground()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            // Header
            Box(
                modifier = Modifier
                    .padding(top = 16.dp)
                    .size(64.dp)
                    .clip(RoundedCornerShape(50.dp))
                    .background(BrandOrange.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Lock,
                    contentDescription = null,
                    tint = BrandOrange,
                    modifier = Modifier.size(26.dp),
                )
            }
            Spacer(Modifier.height(10.dp))
            Text(
                text = "Set a new password",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "Choose a new password for your account. You'll be signed in automatically once it's updated.",
                fontSize = 14.sp,
                color = TextSecondary,
            )
            Spacer(Modifier.height(18.dp))

            // Fields card
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(SurfaceContainer)
                    .border(1.dp, OutlineVariant, RoundedCornerShape(16.dp)),
            ) {
                AuthField(
                    title = "New password",
                    value = newPassword,
                    onValueChange = { newPassword = it },
                    placeholder = "At least 8 characters",
                    keyboardType = KeyboardType.Password,
                    isPassword = true,
                    imeAction = ImeAction.Next,
                )
                Divider()
                AuthField(
                    title = "Confirm password",
                    value = confirmPassword,
                    onValueChange = { confirmPassword = it },
                    placeholder = "Re-enter your new password",
                    keyboardType = KeyboardType.Password,
                    isPassword = true,
                    imeAction = ImeAction.Done,
                )
            }
            Spacer(Modifier.height(18.dp))

            // Submit button — matches EmailAuthScreen's orange-gradient 54-height action button.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp)
                    .clip(RoundedCornerShape(50.dp))
                    .background(
                        if (canSubmit) {
                            Brush.verticalGradient(
                                colors = listOf(BrandOrange, BrandOrange.copy(alpha = 0.85f)),
                            )
                        } else {
                            Brush.verticalGradient(
                                colors = listOf(BrandOrange.copy(alpha = 0.4f), BrandOrange.copy(alpha = 0.3f)),
                            )
                        },
                    )
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        enabled = canSubmit && !isAuthenticating,
                    ) {
                        scope.launch {
                            val ok = auth.updatePassword(newPassword)
                            if (ok) {
                                // Drop the recovery screen and land the user
                                // in the signed-in app.
                                auth.clearPasswordRecovery()
                                onDismiss()
                            }
                            // On failure, leave the user on the screen with
                            // the error visible and the entered password
                            // preserved so they can retry.
                        }
                    },
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (isAuthenticating) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        color = Color.White,
                        strokeWidth = 2.dp,
                    )
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    text = "Update password",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
                Spacer(Modifier.width(8.dp))
                Icon(Icons.Filled.ArrowForward, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
            }
            Spacer(Modifier.height(16.dp))

            // Status messages
            if (lastError != null) {
                Spacer(Modifier.height(12.dp))
                Text(
                    text = lastError ?: "",
                    fontSize = 12.sp,
                    color = Color.Red.copy(alpha = 0.85f),
                )
            }
            if (lastInfo != null) {
                Spacer(Modifier.height(12.dp))
                Text(
                    text = lastInfo ?: "",
                    fontSize = 12.sp,
                    color = TextSecondary,
                )
            }

            Spacer(Modifier.height(40.dp))
        }
    }
}

@Composable
private fun AuthField(
    title: String,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    keyboardType: KeyboardType,
    isPassword: Boolean,
    imeAction: ImeAction = ImeAction.Next,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Text(
            text = title,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextSecondary,
        )
        Spacer(Modifier.height(4.dp))
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = {
                Text(
                    text = placeholder,
                    color = Color.White.copy(alpha = 0.25f),
                    fontSize = 16.sp,
                )
            },
            singleLine = true,
            visualTransformation = if (isPassword) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = imeAction),
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = TextPrimary,
                unfocusedTextColor = TextPrimary,
                cursorColor = BrandOrange,
                focusedBorderColor = Color.Transparent,
                unfocusedBorderColor = Color.Transparent,
                focusedContainerColor = Color.Transparent,
                unfocusedContainerColor = Color.Transparent,
            ),
            textStyle = androidx.compose.ui.text.TextStyle(fontSize = 16.sp, color = TextPrimary),
        )
    }
}

@Composable
private fun Divider() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .height(1.dp)
            .background(Hairline),
    )
}
