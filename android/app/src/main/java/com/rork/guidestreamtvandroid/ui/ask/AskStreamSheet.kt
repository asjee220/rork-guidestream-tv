package com.rork.guidestreamtvandroid.ui.ask

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Movie
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.rork.guidestreamtvandroid.SupabaseConfig
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.local.SpeechInputService
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import com.rork.guidestreamtvandroid.data.remote.AgentTitleMatch
import com.rork.guidestreamtvandroid.data.remote.StreamAgentService
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.theme.Navy
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
import io.github.jan.supabase.auth.auth
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
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
    /**
     * AI-side: titles the agent surfaced for this turn. The renderer draws a
     * horizontal poster rail under the bubble, matching iOS.
     */
    val matches: List<AgentTitleMatch> = emptyList(),
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
    onOpenTitle: (PendingTitleRoute) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val auth = AuthViewModel.get()

    var query by remember { mutableStateOf("") }
    val messages = remember { mutableStateListOf<AskChatMessage>() }
    var isPending by remember { mutableStateOf(false) }

    // Dictation state — mirrors iOS SpeechInputService swap logic. When the
    // device has no recognition service or the mic permission is denied, the
    // mic hides entirely and the sheet degrades to typing only.
    var isDictating by remember { mutableStateOf(false) }
    var micHidden by remember { mutableStateOf(false) }
    val speechAvailable = remember { SpeechInputService.isAvailable(context) }
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current

    val micPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            if (SpeechInputService.start(context) { spoken -> query = spoken }) {
                isDictating = true
            } else {
                micHidden = true
            }
        } else {
            micHidden = true
        }
    }

    // Reset state when sheet closes; auto-focus the field when it opens
    // (mirrors iOS AskStreamSheet.swift focus on appear / clear on close).
    LaunchedEffect(isOpen) {
        if (isOpen) {
            delay(300)
            runCatching { focusRequester.requestFocus() }
        } else {
            query = ""
            messages.clear()
            isPending = false
            SpeechInputService.stop()
            isDictating = false
            focusManager.clearFocus()
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

                Text(
                    text = "Responses are AI-generated and may be inaccurate. Double-check availability before you watch.",
                    fontSize = 11.sp,
                    color = TextSecondary,
                    lineHeight = 15.sp,
                    modifier = Modifier.padding(horizontal = 16.dp).padding(top = 8.dp).padding(bottom = 8.dp),
                )

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
                                    SpeechInputService.stop()
                                    isDictating = false
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
                        items(messages, key = { it.id }) { msg ->
                            MessageBubble(
                                msg = msg,
                                onOpenTitle = { match ->
                                    onClose()
                                    WatchIntentLogger.get().log(
                                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                        titleId = match.id.toString(),
                                        platformId = match.providerName?.lowercase() ?: "ai_match",
                                        metadata = mapOf(
                                            "source" to "ask_stream_ai_match",
                                            "title" to match.title,
                                        ),
                                    )
                                    onOpenTitle(
                                        PendingTitleRoute(
                                            titleId = match.id.toString(),
                                            titleName = match.title,
                                            posterUrl = match.posterUrl,
                                            isTv = match.isTV,
                                        ),
                                    )
                                },
                            )
                        }
                    }
                }

                // Input bar
                val submit: () -> Unit = submit@{
                    if (query.isBlank() || isPending) return@submit
                    SpeechInputService.stop()
                    isDictating = false
                    val text = query.trim()
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
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            capitalization = KeyboardCapitalization.Sentences,
                            imeAction = ImeAction.Send,
                        ),
                        keyboardActions = KeyboardActions(onSend = { submit() }),
                        modifier = Modifier
                            .weight(1f)
                            .padding(horizontal = 12.dp, vertical = 12.dp)
                            .focusRequester(focusRequester),
                        enabled = !isPending,
                        decorationBox = { inner ->
                            // Placeholder overlaid BEHIND the field (Box, not a
                            // preceding sibling) so the caret stays at the start.
                            Box {
                                if (query.isEmpty()) {
                                    Text(
                                        text = "Ask anything about what to watch…",
                                        fontSize = 14.sp,
                                        color = TextTertiary,
                                    )
                                }
                                inner()
                            }
                        },
                    )
                    val showMic = speechAvailable && !micHidden && !isPending &&
                        (query.isBlank() || isDictating)
                    if (showMic) {
                        Box(
                            modifier = Modifier
                                .size(40.dp)
                                .clip(CircleShape)
                                .background(if (isDictating) Color.Red else BrandOrange)
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) {
                                    if (isDictating) {
                                        SpeechInputService.stop()
                                        isDictating = false
                                    } else {
                                        val granted = ContextCompat.checkSelfPermission(
                                            context,
                                            Manifest.permission.RECORD_AUDIO,
                                        ) == PackageManager.PERMISSION_GRANTED
                                        if (granted) {
                                            if (SpeechInputService.start(context) { spoken -> query = spoken }) {
                                                isDictating = true
                                            } else {
                                                micHidden = true
                                            }
                                        } else {
                                            micPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                                        }
                                    }
                                },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                imageVector = if (isDictating) Icons.Filled.Stop else Icons.Filled.Mic,
                                contentDescription = if (isDictating) "Stop dictation" else "Dictate",
                                tint = Color.White,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                    } else {
                        Box(
                            modifier = Modifier
                                .size(40.dp)
                                .clip(CircleShape)
                                .background(if (query.isNotBlank() && !isPending) BrandOrange else GlassFill)
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) { submit() },
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
private fun MessageBubble(
    msg: AskChatMessage,
    onOpenTitle: (AgentTitleMatch) -> Unit,
) {
    val alignment = if (msg.isUser) Alignment.End else Alignment.Start
    val bgColor = if (msg.isUser) BrandOrange else GlassFill
    val textColor = if (msg.isUser) Color.White else TextPrimary

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = alignment,
        verticalArrangement = Arrangement.spacedBy(10.dp),
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
                    lineHeight = 20.sp,
                    color = if (msg.isError) BrandOrange else textColor,
                )
            }
        }

        if (msg.matches.isNotEmpty()) {
            MatchPosterRail(matches = msg.matches, onOpenTitle = onOpenTitle)
        }
    }
}

/**
 * Horizontal rail of poster cards for the titles the agent recommended.
 * Mirrors iOS `matchPosterRail` + `AgentMatchCard`.
 */
@Composable
private fun MatchPosterRail(
    matches: List<AgentTitleMatch>,
    onOpenTitle: (AgentTitleMatch) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        matches.forEach { match ->
            AgentMatchCard(match = match, onClick = { onOpenTitle(match) })
        }
    }
}

@Composable
private fun AgentMatchCard(match: AgentTitleMatch, onClick: () -> Unit) {
    val metaLine = remember(match.year, match.isTV) {
        listOfNotNull(match.year?.toString(), if (match.isTV) "Series" else "Movie")
            .joinToString(" · ")
    }

    Column(
        modifier = Modifier
            .width(124.dp)
            .clip(RoundedCornerShape(10.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            ),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            modifier = Modifier
                .width(124.dp)
                .height(168.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(
                    Brush.verticalGradient(
                        listOf(BrandOrange.copy(alpha = 0.35f), Navy),
                    ),
                ),
        ) {
            if (!match.posterUrl.isNullOrEmpty()) {
                RemoteImage(
                    url = match.posterUrl,
                    contentDescription = match.title,
                    cornerRadius = 10,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Icon(
                    imageVector = Icons.Filled.Movie,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.45f),
                    modifier = Modifier.align(Alignment.Center).size(24.dp),
                )
            }

            val provider = match.providerName
            if (!provider.isNullOrEmpty()) {
                Text(
                    text = provider.uppercase(),
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 0.4.sp,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(6.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(BrandOrange)
                        .padding(horizontal = 6.dp, vertical = 3.dp),
                )
            }
        }

        Text(
            text = match.title,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = metaLine,
            fontSize = 10.sp,
            color = Color.White.copy(alpha = 0.55f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
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
    // Trailing transcript (last 8 committed turns) captured BEFORE appending
    // the current query, so the edge function receives conversation context
    // the same way iOS does. Pending and error bubbles are excluded.
    val history = messages
        .filter { !it.isPending && !it.isError }
        .takeLast(8)
        .map { it.isUser to it.text }

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
                history = history,
                auth = auth,
                context = context,
            )
        }
        // Replace pending message with the prose first so the answer never
        // waits on poster lookups.
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

        // Resolve the recommended titles to TMDB posters and attach them to
        // the same bubble — mirrors iOS AgentResponse.matches.
        if (reply != null) {
            val matches = StreamAgentService.get().resolveTitleMatches(reply)
            if (matches.isNotEmpty()) {
                val current = messages.indexOfFirst { it.id == pendingId }
                if (current >= 0) {
                    messages[current] = messages[current].copy(matches = matches)
                }
            }
        }
    }
}

private suspend fun callAskStream(
    query: String,
    history: List<Pair<Boolean, String>>,
    auth: AuthViewModel,
    context: android.content.Context,
): String? {
    val client = HttpClient {
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
    }
    return try {
        val baseUrl = SupabaseConfig.URL.trim()
        val url = "$baseUrl/functions/v1/askstream"

        val deviceId = try { DeviceIdentity.get().deviceId } catch (_: Exception) { "unknown" }
        val connectedServices = auth.selectedServices.value.toList()

        // Signed-in users send their access token so the edge function can
        // scope grounding and rate limits to the real user (mirrors iOS
        // StreamAgentService); guests fall back to the anon key. The apikey
        // header stays on the anon key in both cases, exactly as iOS does.
        val accessToken = try {
            SupabaseManager.client.auth.currentSessionOrNull()?.accessToken
        } catch (_: Exception) {
            null
        }

        val body = buildJsonObject {
            put(
                "messages",
                buildJsonArray {
                    history.forEach { (isUser, content) ->
                        add(buildJsonObject {
                            put("role", JsonPrimitive(if (isUser) "user" else "assistant"))
                            put("content", JsonPrimitive(content))
                        })
                    }
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
            header(HttpHeaders.Authorization, "Bearer ${accessToken ?: SupabaseConfig.ANON_KEY}")
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
    } finally {
        client.close()
    }
}
