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
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import com.rork.guidestreamtvandroid.ui.theme.BrandWordmark
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import kotlinx.coroutines.launch

enum class EmailAuthMode { SIGN_UP, SIGN_IN }

/**
 * Email + password authentication screen — mirrors iOS EmailAuthView.swift.
 * Defaults to sign-up on first visit, sign-in afterwards. Supports
 * password reset and mode toggle.
 */
@Composable
fun EmailAuthScreen(
    onAuthenticated: () -> Unit,
    onClose: () -> Unit,
) {
    val auth = AuthViewModel.get()
    val scope = rememberCoroutineScope()
    val isAuthenticating by auth.isAuthenticating.collectAsState()
    val lastError by auth.lastError.collectAsState()
    val lastInfo by auth.lastInfo.collectAsState()
    val hasUsedEmailAuth by auth.hasUsedEmailAuth.collectAsState()

    var mode by remember { mutableStateOf(if (hasUsedEmailAuth) EmailAuthMode.SIGN_IN else EmailAuthMode.SIGN_UP) }
    var firstName by remember { mutableStateOf("") }
    var lastName by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var pendingConfirmation by remember { mutableStateOf(false) }
    var showForgotPassword by remember { mutableStateOf(false) }

    val canSubmit = email.trim().contains("@") &&
        email.trim().contains(".") &&
        email.trim().length >= 5 &&
        password.length >= 8 &&
        (mode == EmailAuthMode.SIGN_IN ||
            (firstName.trim().isNotEmpty() &&
                lastName.trim().isNotEmpty() &&
                password == confirmPassword))

    Box(modifier = Modifier.fillMaxSize()) {
        BrandBackground()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp, bottom = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onClose) {
                    Icon(Icons.Filled.Close, contentDescription = "Close", tint = TextSecondary)
                }
                Spacer(Modifier.weight(1f))
                BrandWordmark(size = com.rork.guidestreamtvandroid.ui.theme.WordmarkSize.NAV)
                Spacer(Modifier.weight(1f))
                Spacer(Modifier.size(48.dp))
            }

            // Header
            Text(
                text = if (mode == EmailAuthMode.SIGN_UP) "Create your account" else "Welcome back",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = if (mode == EmailAuthMode.SIGN_UP)
                    "Use your email to save your services and pick up where you left off on any device."
                else
                    "Sign in with the email you used last time.",
                fontSize = 14.sp,
                color = TextSecondary,
            )
            Spacer(Modifier.height(18.dp))

            if (pendingConfirmation) {
                // Confirmation banner
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(BrandOrange.copy(alpha = 0.10f))
                        .border(1.dp, BrandOrange.copy(alpha = 0.35f), RoundedCornerShape(14.dp))
                        .padding(14.dp),
                ) {
                    Icon(
                        imageVector = Icons.Filled.Email,
                        contentDescription = null,
                        tint = BrandOrange,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(Modifier.width(10.dp))
                    Column {
                        Text(
                            text = "Check your inbox",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = TextPrimary,
                        )
                        Text(
                            text = "We just sent a confirmation link to $email. Tap it, then come back here and sign in.",
                            fontSize = 12.sp,
                            color = TextSecondary,
                        )
                    }
                }
                Spacer(Modifier.height(18.dp))
            }

            // Fields card
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(Color.White.copy(alpha = 0.04f))
                    .border(1.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(16.dp)),
            ) {
                if (mode == EmailAuthMode.SIGN_UP) {
                    AuthField(
                        title = "First name",
                        value = firstName,
                        onValueChange = { firstName = it },
                        placeholder = "Jane",
                        keyboardType = KeyboardType.Text,
                        isPassword = false,
                    )
                    Divider()
                    AuthField(
                        title = "Last name",
                        value = lastName,
                        onValueChange = { lastName = it },
                        placeholder = "Smith",
                        keyboardType = KeyboardType.Text,
                        isPassword = false,
                    )
                    Divider()
                }
                AuthField(
                    title = "Email",
                    value = email,
                    onValueChange = { email = it },
                    placeholder = "you@example.com",
                    keyboardType = KeyboardType.Email,
                    isPassword = false,
                )
                Divider()
                AuthField(
                    title = "Password",
                    value = password,
                    onValueChange = { password = it },
                    placeholder = if (mode == EmailAuthMode.SIGN_UP) "At least 8 characters" else "Your password",
                    keyboardType = KeyboardType.Password,
                    isPassword = true,
                )
                if (mode == EmailAuthMode.SIGN_UP) {
                    Divider()
                    AuthField(
                        title = "Confirm password",
                        value = confirmPassword,
                        onValueChange = { confirmPassword = it },
                        placeholder = "Re-enter your password",
                        keyboardType = KeyboardType.Password,
                        isPassword = true,
                    )
                }
            }
            Spacer(Modifier.height(18.dp))

            // Submit button
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
                            val trimmedEmail = email.trim()
                            val trimmedFirst = firstName.trim()
                            val trimmedLast = lastName.trim()
                            auth.lastError
                            if (mode == EmailAuthMode.SIGN_UP) {
                                val ok = auth.signUpWithEmail(trimmedEmail, password, trimmedFirst, trimmedLast)
                                if (ok) { onAuthenticated(); return@launch }
                                if (auth.isAuthenticated.value) { onAuthenticated(); return@launch }
                                if (auth.lastInfo.value != null) {
                                    pendingConfirmation = true
                                    mode = EmailAuthMode.SIGN_IN
                                }
                            } else {
                                val ok = auth.signInWithEmail(trimmedEmail, password)
                                if (ok) onAuthenticated()
                            }
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
                    text = if (mode == EmailAuthMode.SIGN_UP) "Create account" else "Sign in",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
                Spacer(Modifier.width(8.dp))
                Icon(Icons.Filled.ArrowForward, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
            }
            Spacer(Modifier.height(16.dp))

            // Forgot password
            if (mode == EmailAuthMode.SIGN_IN) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                ) {
                    if (showForgotPassword) {
                        Text(
                            text = "Send reset email",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = BrandOrange,
                            modifier = Modifier
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) {
                                    scope.launch {
                                        auth.sendPasswordReset(email.trim())
                                    }
                                }
                                .padding(8.dp),
                        )
                    } else {
                        Text(
                            text = "Forgot password?",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                            color = BrandOrange,
                            modifier = Modifier
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) { showForgotPassword = true }
                                .padding(8.dp),
                        )
                    }
                }
            }

            // Mode toggle
            Spacer(Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = if (mode == EmailAuthMode.SIGN_UP) "Already have an account?" else "New here?",
                    fontSize = 13.sp,
                    color = TextSecondary,
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    text = if (mode == EmailAuthMode.SIGN_UP) "Sign in" else "Create account",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = BrandOrange,
                    modifier = Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) {
                            // Clear stale messages
                            pendingConfirmation = false
                            mode = if (mode == EmailAuthMode.SIGN_UP) EmailAuthMode.SIGN_IN else EmailAuthMode.SIGN_UP
                        }
                        .padding(4.dp),
                )
            }

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
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = ImeAction.Next),
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
            .background(Color.White.copy(alpha = 0.06f)),
    )
}
