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
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.SocialViewModel
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.SheetLevel
import com.rork.guidestreamtvandroid.ui.theme.SheetSurfaceRaised
import com.rork.guidestreamtvandroid.ui.components.GsSheetDragHandle
import com.rork.guidestreamtvandroid.ui.components.GsSheetHeader
import com.rork.guidestreamtvandroid.ui.theme.Hairline
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import com.rork.guidestreamtvandroid.ui.theme.sheetTopInset
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
    val auth = AuthViewModel.get()
    val scope = rememberCoroutineScope()
    val myDeviceId = remember { DeviceIdentity.get().deviceId }
    val myUserId = remember { auth.currentUserId }

    val commentsMap by social.commentsByTitle.collectAsStateWithLifecycle()
    val countsMap by social.commentCounts.collectAsStateWithLifecycle()
    val loadingSet by social.loadingComments.collectAsStateWithLifecycle()
    val postingSet by social.postingComment.collectAsStateWithLifecycle()
    val profanityBlockedFlag by social.lastPostWasProfanityBlocked.collectAsStateWithLifecycle()

    val comments = commentsMap[titleId] ?: emptyList()
    val total = countsMap[titleId] ?: comments.size
    val isLoading = loadingSet.contains(titleId) && comments.isEmpty()
    val isPosting = postingSet.contains(titleId)

    var draft by remember { mutableStateOf("") }
    var profanityBlocked by remember { mutableStateOf(false) }
    var transientMessage by remember { mutableStateOf<String?>(null) }
    var reportTarget by remember { mutableStateOf<SocialViewModel.TitleComment?>(null) }
    var showReportReasons by remember { mutableStateOf(false) }

    LaunchedEffect(titleId) {
        // Once-per-session block-list load so blocked authors are filtered
        // out of the thread before it renders.
        social.loadBlockedUsers()
        social.loadComments(titleId)
        social.refreshCounts(titleId)
    }

    fun showTransient(text: String) {
        transientMessage = text
        scope.launch {
            kotlinx.coroutines.delay(2500L)
            if (transientMessage == text) transientMessage = null
        }
    }

    fun isOwnComment(c: SocialViewModel.TitleComment): Boolean {
        val uid = myUserId
        if (uid != null && c.userId == uid) return true
        if (c.userId == null && c.deviceId == myDeviceId) return true
        return false
    }

    fun canBlockAuthor(c: SocialViewModel.TitleComment): Boolean =
        !c.userId.isNullOrBlank() || !c.deviceId.isNullOrBlank()

    fun reportComment(c: SocialViewModel.TitleComment, reason: String) {
        reportTarget = null
        showReportReasons = false
        scope.launch {
            val before = (commentsMap[titleId] ?: emptyList()).size
            social.reportComment(c, reason)
            val after = (social.commentsByTitle.value[titleId] ?: emptyList()).size
            if (after < before) showTransient("Thanks — we’ll review this comment.")
            else showTransient("Couldn’t report right now. Try again later.")
        }
    }

    fun blockAuthor(c: SocialViewModel.TitleComment) {
        scope.launch {
            val before = (commentsMap[titleId] ?: emptyList()).size
            social.blockUser(c)
            val after = (social.commentsByTitle.value[titleId] ?: emptyList()).size
            if (after < before) showTransient("This person’s comments are now hidden.")
            else showTransient("Couldn’t block right now. Try again later.")
        }
    }

    fun deleteOwn(c: SocialViewModel.TitleComment) {
        scope.launch {
            val before = (commentsMap[titleId] ?: emptyList()).size
            social.deleteComment(c)
            val after = (social.commentsByTitle.value[titleId] ?: emptyList()).size
            if (after < before) showTransient("Comment deleted.")
            else showTransient("Couldn’t delete right now. Try again later.")
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = SheetSurfaceRaised,
        scrimColor = Color.Black.copy(alpha = 0.60f),
        tonalElevation = 0.dp,
        dragHandle = { GsSheetDragHandle(level = SheetLevel.Raised) },
        contentWindowInsets = { sheetTopInset() },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .imePadding()
                .padding(bottom = 8.dp),
        ) {
            // Header
            GsSheetHeader(
                title = "Comments",
                subtitle = subtitle ?: title,
                trailing = {
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
                    Spacer(Modifier.width(12.dp))
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
                },
            )

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
                            CommentRow(
                                comment = comment,
                                isOwnComment = isOwnComment(comment),
                                canBlockAuthor = canBlockAuthor(comment),
                                onReport = {
                                    if (isOwnComment(comment)) return@CommentRow
                                    reportTarget = comment
                                    showReportReasons = true
                                },
                                onBlock = {
                                    if (isOwnComment(comment) || !canBlockAuthor(comment)) return@CommentRow
                                    blockAuthor(comment)
                                },
                                onDelete = {
                                    if (!isOwnComment(comment)) return@CommentRow
                                    deleteOwn(comment)
                                },
                            )
                        }
                    }
                    // Report-reason dropdown — anchored to the sheet, mirrors
                    // the iOS confirmationDialog with three choices.
                    DropdownMenu(
                        expanded = showReportReasons && reportTarget != null,
                        onDismissRequest = {
                            showReportReasons = false
                            reportTarget = null
                        },
                    ) {
                        DropdownMenuItem(
                            text = { Text("Spam", color = TextPrimary) },
                            onClick = { reportTarget?.let { reportComment(it, "Spam") } },
                        )
                        DropdownMenuItem(
                            text = { Text("Harassment", color = TextPrimary) },
                            onClick = { reportTarget?.let { reportComment(it, "Harassment") } },
                        )
                        DropdownMenuItem(
                            text = { Text("Inappropriate", color = TextPrimary) },
                            onClick = { reportTarget?.let { reportComment(it, "Inappropriate") } },
                        )
                    }
                }
            }

            // Input bar
            if (profanityBlocked) {
                Text(
                    text = "Please keep it respectful — that comment can’t be posted",
                    fontSize = 12.sp,
                    color = BrandOrange,
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 4.dp),
                )
            }
            transientMessage?.let { msg ->
                Text(
                    text = msg,
                    fontSize = 12.sp,
                    color = TextSecondary,
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 4.dp),
                )
            }
            // Quiet community-guidelines caption — matches the dimmed
            // secondary-text treatment used elsewhere in this sheet.
            Text(
                text = "By posting you agree to our community guidelines — no objectionable content or abuse",
                fontSize = 10.sp,
                color = TextTertiary,
                maxLines = 2,
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 4.dp),
            )
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
                            profanityBlocked = false
                            scope.launch {
                                val ok = social.postComment(titleId, body)
                                if (!ok) {
                                    // Restore the draft so the user can edit and
                                    // retry. When the profanity gate tripped, show
                                    // the inline respectful message as well.
                                    draft = body
                                    if (profanityBlockedFlag) profanityBlocked = true
                                }
                            }
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
private fun CommentRow(
    comment: SocialViewModel.TitleComment,
    isOwnComment: Boolean,
    canBlockAuthor: Boolean,
    onReport: () -> Unit,
    onBlock: () -> Unit,
    onDelete: () -> Unit,
) {
    val name = comment.displayName?.takeIf { it.isNotBlank() } ?: "Guest"
    val seed = comment.userId ?: comment.deviceId ?: comment.id
    val initials = comment.initials?.takeIf { it.isNotBlank() } ?: initialsOf(name)
    var menuExpanded by remember { mutableStateOf(false) }
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
        // Trailing ellipsis overflow control — same glassmorphism, brand
        // accent, and sizing as the close button in the header.
        Box {
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(TextPrimary.copy(alpha = 0.10f))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { menuExpanded = true },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.MoreVert,
                    contentDescription = if (isOwnComment) "Comment options" else "Report or block comment",
                    tint = TextPrimary.copy(alpha = 0.85f),
                    modifier = Modifier.size(16.dp),
                )
            }
            DropdownMenu(
                expanded = menuExpanded,
                onDismissRequest = { menuExpanded = false },
            ) {
                if (isOwnComment) {
                    DropdownMenuItem(
                        text = { Text("Delete", color = BrandOrange) },
                        onClick = {
                            menuExpanded = false
                            onDelete()
                        },
                    )
                } else {
                    DropdownMenuItem(
                        text = { Text("Report", color = TextPrimary) },
                        onClick = {
                            menuExpanded = false
                            onReport()
                        },
                    )
                    if (canBlockAuthor) {
                        DropdownMenuItem(
                            text = { Text("Block this person", color = BrandOrange) },
                            onClick = {
                                menuExpanded = false
                                onBlock()
                            },
                        )
                    }
                }
            }
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
