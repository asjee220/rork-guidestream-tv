package com.rork.guidestreamtvandroid.ui.comments

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
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
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.repository.SocialViewModel
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Hairline
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.absoluteValue

/**
 * Comments bottom sheet for a title. Reads/writes via [SocialViewModel] so the
 * same thread appears on iOS and Android. Header shows a poster thumbnail, the
 * comment count, and a close (X) button; the body is the thread; the footer is
 * a capsule input bar. Mirrors iOS TitleCommentsSheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TitleCommentsSheet(
    titleId: String,
    title: String,
    subtitle: String? = null,
    posterUrl: String? = null,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val social = SocialViewModel.get()
    val scope = rememberCoroutineScope()

    val commentsMap by social.commentsByTitle.collectAsStateWithLifecycle()
    val countsMap by social.commentCounts.collectAsStateWithLifecycle()
    val loadingSet by social.loadingComments.collectAsStateWithLifecycle()
    val postingSet by social.postingComment.collectAsStateWithLifecycle()

    val comments = commentsMap[titleId] ?: emptyList()
    val total = countsMap[titleId] ?: comments.size
    val isLoading = loadingSet.contains(titleId) && comments.isEmpty()
    val isPosting = postingSet.contains(titleId)

    var draft by remember { mutableStateOf("") }

    LaunchedEffect(titleId) {
        social.loadComments(titleId)
        social.refreshCounts(titleId)
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(red = 0x0A, green = 0x10, blue = 0x1A),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .imePadding()
                .padding(bottom = 8.dp),
        ) {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(top = 4.dp, bottom = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (posterUrl != null) {
                    RemoteImage(
                        url = posterUrl,
                        contentDescription = title,
                        modifier = Modifier.size(width = 44.dp, height = 60.dp),
                        cornerRadius = 8,
                        placeholderText = title.take(2).uppercase(),
                        placeholderFontSize = 15.sp,
                    )
                }
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(
                        text = "Comments",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Black,
                        color = TextPrimary,
                    )
                    Text(
                        text = subtitle ?: title,
                        fontSize = 13.sp,
                        color = TextPrimary.copy(alpha = 0.55f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(TextPrimary.copy(alpha = 0.10f))
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                ) {
                    Text(
                        text = formatCount(total),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary,
                    )
                }
                IconButton(
                    onClick = onDismiss,
                    modifier = Modifier
                        .size(30.dp)
                        .clip(CircleShape)
                        .background(TextPrimary.copy(alpha = 0.10f)),
                ) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "Close comments",
                        tint = TextPrimary.copy(alpha = 0.85f),
                        modifier = Modifier.size(16.dp),
                    )
                }
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .height(1.dp)
                    .background(Hairline),
            )

            // Thread
            when {
                isLoading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(color = BrandOrange)
                    }
                }
                comments.isEmpty() -> {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp)
                            .padding(horizontal = 24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            text = "Start the conversation",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = TextPrimary,
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            text = "Be the first to share what you think about $title.",
                            fontSize = 13.sp,
                            color = TextSecondary,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 180.dp, max = 520.dp),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(
                            horizontal = 20.dp,
                            vertical = 14.dp,
                        ),
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        items(comments, key = { it.id }) { comment ->
                            CommentRow(comment)
                        }
                    }
                }
            }

            // Input bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(34.dp)
                        .clip(CircleShape)
                        .background(BrandOrange),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = currentUserInitials(),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                }
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(CircleShape)
                        .background(TextPrimary.copy(alpha = 0.08f))
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    if (draft.isEmpty()) {
                        Text(
                            text = "Add a comment…",
                            fontSize = 14.sp,
                            color = TextSecondary,
                        )
                    }
                    BasicTextField(
                        value = draft,
                        onValueChange = { draft = it },
                        textStyle = TextStyle(color = TextPrimary, fontSize = 14.sp),
                        cursorBrush = SolidColor(BrandOrange),
                        maxLines = 4,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                val canSend = draft.trim().isNotEmpty() && !isPosting
                Box(
                    modifier = Modifier
                        .size(38.dp)
                        .clip(CircleShape)
                        .background(if (canSend) BrandOrange else TextPrimary.copy(alpha = 0.08f))
                        .clickable(
                            enabled = canSend,
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) {
                            val body = draft.trim()
                            draft = ""
                            scope.launch { social.postComment(titleId, body) }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.Send,
                        contentDescription = "Send",
                        tint = Color.White,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun CommentRow(comment: SocialViewModel.TitleComment) {
    val name = comment.displayName?.takeIf { it.isNotBlank() } ?: "Guest"
    val seed = comment.userId ?: comment.deviceId ?: comment.id
    val initials = comment.initials?.takeIf { it.isNotBlank() } ?: initialsOf(name)
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(avatarColor(seed)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = initials,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = name,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                val stamp = relativeTime(comment.createdAt)
                if (stamp.isNotEmpty()) {
                    Text(
                        text = stamp,
                        fontSize = 11.sp,
                        color = TextTertiary,
                    )
                }
            }
            Text(
                text = comment.body,
                fontSize = 13.sp,
                color = TextPrimary.copy(alpha = 0.85f),
                lineHeight = 19.sp,
            )
        }
    }
}

private val avatarPalette = listOf(
    Color(red = 0.95f, green = 0.45f, blue = 0.10f),
    Color(red = 0.18f, green = 0.55f, blue = 0.95f),
    Color(red = 0.60f, green = 0.25f, blue = 0.85f),
    Color(red = 0.20f, green = 0.78f, blue = 0.55f),
    Color(red = 0.95f, green = 0.30f, blue = 0.45f),
    Color(red = 0.30f, green = 0.70f, blue = 0.90f),
)

private fun avatarColor(seed: String): Color {
    if (seed.isEmpty()) return avatarPalette[0]
    return avatarPalette[seed.hashCode().absoluteValue % avatarPalette.size]
}

private fun initialsOf(name: String): String =
    name.split(Regex("\\s+"))
        .filter { it.isNotEmpty() }
        .take(2)
        .map { it.first().uppercaseChar() }
        .joinToString("")
        .ifEmpty { "?" }

private fun currentUserInitials(): String {
    val auth = com.rork.guidestreamtvandroid.data.repository.AuthViewModel.get()
    val name = auth.displayName.value?.trim()?.takeIf { it.isNotEmpty() }
        ?: listOf(auth.firstName.value, auth.lastName.value)
            .mapNotNull { it?.trim() }
            .filter { it.isNotEmpty() }
            .joinToString(" ")
            .takeIf { it.isNotEmpty() }
        ?: auth.email?.substringBefore("@")?.takeIf { it.isNotEmpty() }
        ?: "You"
    return initialsOf(name)
}

private fun relativeTime(iso: String?): String {
    if (iso.isNullOrBlank()) return ""
    return try {
        val trimmed = iso.take(19)
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val date: Date = fmt.parse(trimmed) ?: return ""
        val diff = System.currentTimeMillis() - date.time
        when {
            diff < 60_000L -> "now"
            diff < 3_600_000L -> "${diff / 60_000L}m"
            diff < 86_400_000L -> "${diff / 3_600_000L}h"
            diff < 604_800_000L -> "${diff / 86_400_000L}d"
            else -> "${diff / 604_800_000L}w"
        }
    } catch (_: Exception) {
        ""
    }
}

private fun formatCount(n: Int): String = when {
    n >= 1_000_000 -> String.format(Locale.US, "%.1fM", n / 1_000_000.0)
    n >= 1_000 -> String.format(Locale.US, "%.1fK", n / 1_000.0)
    else -> n.toString()
}
