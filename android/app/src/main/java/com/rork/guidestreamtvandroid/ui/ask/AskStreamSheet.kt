package com.rork.guidestreamtvandroid.ui.ask

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
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
import com.rork.guidestreamtvandroid.SupabaseConfig
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject

/**
 * Ask Stream chat message — mirrors iOS AskChatMessage.
 */
data class AskChatMessage(
    val id: String,
    val isUser: Boolean,
    val text: String,
    val isPending: Boolean = false,
    val isError: Boolean = false,
)

private val askSuggestions = listOf(
    "What should I watch tonight?",
    "Shows like Breaking Bad on my services",
    "Build me a binge queue",
    "What's everyone watching this week?",
)

@Serializable
private data class AskStreamResponse(
    val reply: String? = null,
    @SerialName("error") val error: String? = null,
)

/**
 * Ask Stream bottom sheet — hybrid search + AI.
 * Mirrors iOS AskStreamSheet.swift. Calls the `askstream` Supabase edge function.
 */
@Composable
fun AskStreamSheet(
    isOpen: Boolean,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val auth = AuthViewModel.get()

    var query by remember { mutableStateOf("") }
    val messages = remember { mutableStateListOf<AskChatMessage>() }
    var isPending by remember { mutableStateOf(false) }

    // Reset state when sheet closes
    LaunchedEffect(isOpen) {
        if (!isOpen) {
            query = ""
            messages.clear()
            isPending = false
        }
    }

    // Scrim + sheet
    Box(modifier = modifier.fillMaxSize()) {
        // Scrim
        AnimatedVisibility(
            visible = isOpen,
            enter = fadeIn(),
            exit = fadeOut(),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.4f))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onClose() },
            )
        }

        // Sheet
        AnimatedVisibility(
            visible = isOpen,
            enter = slideInVertically { it } + fadeIn(),
            exit = slideOutVertically { it } + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxSize(0.82f)
                    .clip(RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp))
                    .background(Color(red = 0x04, green = 0x09, blue = 0x0F))
                    .imePadding()
                    .navigationBarsPadding(),
            ) {
                // Header
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Filled.AutoAwesome,
                        contentDescription = null,
                        tint = BrandOrange,
                        modifier = Modifier.size(20.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = "Ask Stream",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Black,
                        color = TextPrimary,
                    )
                    Spacer(Modifier.weight(1f))
                    Box(
                        modifier = Modifier
                            .size(32.dp)
                            .clip(CircleShape)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { onClose() },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Close,
                            contentDescription = "Close",
                            tint = TextSecondary,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }

                // Messages list
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    if (messages.isEmpty()) {
                        item {
                            Text(
                                text = "Ask me anything about what to watch. I'll ground my answer in your follows and connected services.",
                                fontSize = 14.sp,
                                color = TextSecondary,
                                modifier = Modifier.padding(vertical = 8.dp),
                            )
                        }
                        items(askSuggestions) { suggestion ->
                            SuggestionChip(
                                text = suggestion,
                                onClick = {
                                    query = suggestion
                                    sendMessage(
                                        text = suggestion,
                                        scope = scope,
                                        auth = auth,
                                        context = context,
                                        messages = messages,
                                        onPendingChange = { isPending = it },
                                    )
                                },
                            )
                        }
                    } else {
                        items(messages) { msg ->
                            MessageBubble(msg)
                        }
                    }
                }

                // Input bar
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .glassCard(cornerRadius = 0)
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    BasicTextField(
                        value = query,
                        onValueChange = { query = it },
                        textStyle = TextStyle(
                            color = TextPrimary,
                            fontSize = 15.sp,
                        ),
                        cursorBrush = SolidColor(BrandOrange),
                        modifier = Modifier
                            .weight(1f)
                            .padding(horizontal = 12.dp, vertical = 12.dp),
                        enabled = !isPending,
                    )
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(if (query.isNotBlank() && !isPending) BrandOrange else GlassFill)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) {
                                if (query.isNotBlank() && !isPending) {
                                    val text = query
                                    query = ""
                                    sendMessage(
                                        text = text,
                                        scope = scope,
                                        auth = auth,
                                        context = context,
                                        messages = messages,
                                        onPendingChange = { isPending = it },
                                    )
                                }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        if (isPending) {
                            CircularProgressIndicator(
                                color = TextSecondary,
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                            )
                        } else {
                            Icon(
                                imageVector = Icons.Filled.Send,
                                contentDescription = "Send",
                                tint = if (query.isNotBlank()) Color.White else TextTertiary,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SuggestionChip(text: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(GlassFill)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
    ) {
        Text(
            text = text,
            fontSize = 14.sp,
            color = TextPrimary,
        )
    }
}

@Composable
private fun MessageBubble(msg: AskChatMessage) {
    val alignment = if (msg.isUser) Alignment.End else Alignment.Start
    val bgColor = if (msg.isUser) BrandOrange else GlassFill
    val textColor = if (msg.isUser) Color.White else TextPrimary

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = alignment,
    ) {
        Box(
            modifier = Modifier
                .clip(
                    RoundedCornerShape(
                        topStart = 16.dp,
                        topEnd = 16.dp,
                        bottomStart = if (msg.isUser) 16.dp else 4.dp,
                        bottomEnd = if (msg.isUser) 4.dp else 16.dp,
                    ),
                )
                .background(bgColor)
                .padding(horizontal = 14.dp, vertical = 10.dp),
        ) {
            if (msg.isPending) {
                Text(
                    text = "Thinking…",
                    fontSize = 14.sp,
                    color = TextSecondary,
                    fontStyle = androidx.compose.ui.text.font.FontStyle.Italic,
                )
            } else {
                Text(
                    text = msg.text,
                    fontSize = 14.sp,
                    color = if (msg.isError) BrandOrange else textColor,
                )
            }
        }
    }
}

/**
 * Sends a user message and calls the askstream edge function.
 */
private fun sendMessage(
    text: String,
    scope: kotlinx.coroutines.CoroutineScope,
    auth: AuthViewModel,
    context: android.content.Context,
    messages: androidx.compose.runtime.snapshots.SnapshotStateList<AskChatMessage>,
    onPendingChange: (Boolean) -> Unit,
) {
    val userMsgId = "user-${System.currentTimeMillis()}"
    messages.add(AskChatMessage(id = userMsgId, isUser = true, text = text))
    onPendingChange(true)

    // Log the query
    WatchIntentLogger.get().log(
        WatchIntentLogger.IntentEventType.ASK_STREAM_QUERY,
        metadata = mapOf("query" to text),
    )

    val pendingId = "ai-${System.currentTimeMillis()}"
    messages.add(AskChatMessage(id = pendingId, isUser = false, text = "", isPending = true))

    scope.launch {
        val reply = withContext(Dispatchers.IO) {
            callAskStream(
                query = text,
                auth = auth,
                context = context,
            )
        }
        // Replace pending message
        val idx = messages.indexOfFirst { it.id == pendingId }
        if (idx >= 0) {
            messages[idx] = AskChatMessage(
                id = pendingId,
                isUser = false,
                text = reply ?: "Couldn't reach the guide right now. Check your connection and try again.",
                isPending = false,
                isError = reply == null,
            )
        }
        onPendingChange(false)
    }
}

private suspend fun callAskStream(
    query: String,
    auth: AuthViewModel,
    context: android.content.Context,
): String? {
    return try {
        val client = HttpClient {
            install(ContentNegotiation) {
                json(Json { ignoreUnknownKeys = true })
            }
        }
        val baseUrl = SupabaseConfig.URL.trim()
        val url = "$baseUrl/functions/v1/askstream"

        val deviceId = try { DeviceIdentity.get().deviceId } catch (_: Exception) { "unknown" }
        val connectedServices = auth.selectedServices.value.toList()

        val body = buildJsonObject {
            put(
                "messages",
                buildJsonArray {
                    add(buildJsonObject {
                        put("role", JsonPrimitive("user"))
                        put("content", JsonPrimitive(query))
                    })
                },
            )
            put("device_id", JsonPrimitive(deviceId))
            if (connectedServices.isNotEmpty()) {
                put(
                    "connected_services",
                    JsonArray(connectedServices.map { JsonPrimitive(it) }),
                )
            }
        }

        val response: HttpResponse = client.post(url) {
            contentType(ContentType.Application.Json)
            header(HttpHeaders.ContentType, "application/json")
            header("apikey", SupabaseConfig.ANON_KEY)
            header(HttpHeaders.Authorization, "Bearer ${SupabaseConfig.ANON_KEY}")
            setBody(body.toString())
        }

        if (response.status.value == 200) {
            val resp: AskStreamResponse = response.body()
            resp.reply ?: resp.error ?: "No response."
        } else {
            null
        }
    } catch (_: Exception) {
        null
    }
}
