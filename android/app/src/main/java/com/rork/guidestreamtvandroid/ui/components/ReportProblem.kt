package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.remote.ContentReportKind
import com.rork.guidestreamtvandroid.data.remote.ContentReportService
import com.rork.guidestreamtvandroid.data.remote.DeepLinkReturnCheck
import com.rork.guidestreamtvandroid.data.remote.ReportCenter
import com.rork.guidestreamtvandroid.data.remote.ReportContext
import com.rork.guidestreamtvandroid.data.remote.ReportReason
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.SheetLevel
import com.rork.guidestreamtvandroid.ui.theme.SheetSurfaceBase
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.sheetTopInset
import kotlinx.coroutines.launch

/** A / D — the quiet inline link. */
@Composable
fun ReportProblemLink(
    context: ReportContext,
    modifier: Modifier = Modifier,
    prompt: String = "Wrong service or link?",
) {
    Row(
        modifier = modifier
            .heightIn(min = 44.dp)
            .clickable(role = Role.Button, onClickLabel = "Report a problem") { ReportCenter.open(context) },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(Icons.Outlined.Flag, contentDescription = null, tint = TextSecondary, modifier = Modifier.size(14.dp))
        Text(prompt, fontSize = 13.sp, color = TextSecondary)
        Text("Report it", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = BrandOrange)
    }
}

/** Mounted once at the app root; draws whichever report UI ReportCenter asks for. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportHost() {
    val report by ReportCenter.report.collectAsState()
    val returnCheck by ReportCenter.returnCheck.collectAsState()

    returnCheck?.let { p ->
        val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { ReportCenter.closeReturnCheck() },
            sheetState = state,
            containerColor = SheetSurfaceBase,
            scrimColor = Color.Black.copy(alpha = 0.5f),
            tonalElevation = 0.dp,
            dragHandle = { GsSheetDragHandle(level = SheetLevel.Base) },
            contentWindowInsets = { sheetTopInset() },
        ) {
            DeepLinkReturnCard(
                pending = p,
                onYes = {
                    DeepLinkReturnCheck.record(p, opened = true)
                    ReportCenter.closeReturnCheck()
                },
                onNo = {
                    DeepLinkReturnCheck.record(p, opened = false)
                    ReportCenter.closeReturnCheck()
                    ReportCenter.open(p.reportContext)
                },
                onDismiss = { ReportCenter.closeReturnCheck() },
            )
        }
    }

    report?.let { ctx ->
        val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { ReportCenter.closeReport() },
            sheetState = state,
            containerColor = SheetSurfaceBase,
            scrimColor = Color.Black.copy(alpha = 0.6f),
            tonalElevation = 0.dp,
            dragHandle = { GsSheetDragHandle(level = SheetLevel.Base) },
            contentWindowInsets = { sheetTopInset() },
        ) {
            ReportProblemSheetContent(ctx = ctx, onClose = { ReportCenter.closeReport() })
        }
    }
}

@Composable
private fun DeepLinkReturnCard(
    pending: DeepLinkReturnCheck.Pending,
    onYes: () -> Unit,
    onNo: () -> Unit,
    onDismiss: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(start = 20.dp, end = 12.dp, bottom = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f).padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    "Did ${pending.platform} open ${pending.title}?",
                    fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 2,
                )
                Text("Helps us keep links accurate", fontSize = 13.sp, color = TextSecondary)
            }
            IconButton(onClick = onDismiss) {
                Icon(Icons.Filled.Close, contentDescription = "Dismiss", tint = TextSecondary)
            }
        }
        Row(Modifier.padding(end = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color.White.copy(alpha = 0.08f))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                    .clickable(role = Role.Button, onClick = onYes),
                contentAlignment = Alignment.Center,
            ) { Text("Yes, it worked", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color.White) }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(BrandOrange)
                    .clickable(role = Role.Button, onClick = onNo),
                contentAlignment = Alignment.Center,
            ) { Text("No, report it", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.Black) }
        }
    }
}

@Composable
private fun ReportProblemSheetContent(ctx: ReportContext, onClose: () -> Unit) {
    var reason by remember(ctx) { mutableStateOf(ctx.preselected) }
    var note by remember(ctx) { mutableStateOf("") }
    var sending by remember(ctx) { mutableStateOf(false) }
    var sent by remember(ctx) { mutableStateOf(false) }
    var failed by remember(ctx) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    if (sent) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 32.dp, vertical = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(
                Modifier.size(64.dp).clip(CircleShape).background(BrandOrange),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.Check, contentDescription = null, tint = Color.Black, modifier = Modifier.size(30.dp)) }
            Text("Thanks — we’re on it", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Text(
                ctx.providerName?.let { "We’ll check ${ctx.titleName} on $it and fix it for everyone." }
                    ?: "We’ll check ${ctx.titleName} and fix it for everyone.",
                fontSize = 15.sp, color = Color.White.copy(alpha = 0.75f), textAlign = TextAlign.Center,
            )
            Box(
                modifier = Modifier
                    .padding(top = 8.dp)
                    .width(200.dp)
                    .height(48.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(BrandOrange)
                    .clickable(role = Role.Button, onClick = onClose),
                contentAlignment = Alignment.Center,
            ) { Text("Done", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color.Black) }
        }
        return
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(start = 20.dp, end = 20.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Report a problem", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Color.White, modifier = Modifier.weight(1f))
            IconButton(onClick = onClose) {
                Icon(Icons.Filled.Close, contentDescription = "Close", tint = TextSecondary)
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .background(Color.White.copy(alpha = 0.05f))
                .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(ctx.titleName, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 2)
            ctx.providerName?.takeIf { it.isNotBlank() }?.let { Text(it, fontSize = 13.sp, color = TextSecondary) }
        }

        Text(
            "WHAT'S WRONG?", fontSize = 12.sp, fontWeight = FontWeight.Bold,
            letterSpacing = 1.2.sp, color = Color.White.copy(alpha = 0.35f),
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .background(Color.White.copy(alpha = 0.05f))
                .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp)),
        ) {
            ReportReason.options(ctx.kind).forEachIndexed { i, option ->
                if (i > 0) HorizontalDivider(color = Color.White.copy(alpha = 0.08f))
                val selected = reason == option
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .background(if (selected) Color.White.copy(alpha = 0.06f) else Color.Transparent)
                        .clickable(role = Role.RadioButton) { reason = option }
                        .padding(horizontal = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(
                        Modifier
                            .size(20.dp)
                            .border(2.dp, if (selected) BrandOrange else Color.White.copy(alpha = 0.3f), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (selected) Box(Modifier.size(10.dp).clip(CircleShape).background(BrandOrange))
                    }
                    Text(option.label, fontSize = 15.sp, color = Color.White)
                }
            }
        }

        Text("Anything else? (optional)", fontSize = 13.sp, color = TextSecondary)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 72.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color.White.copy(alpha = 0.05f))
                .border(1.dp, Color.White.copy(alpha = 0.1f), RoundedCornerShape(12.dp))
                .padding(12.dp),
        ) {
            if (note.isEmpty()) {
                Text(
                    if (ctx.kind == ContentReportKind.SPORTS) "e.g. It’s on ESPN, not FOX" else "e.g. It’s on Netflix now",
                    fontSize = 15.sp, color = Color.White.copy(alpha = 0.35f),
                )
            }
            BasicTextField(
                value = note,
                onValueChange = { if (it.length <= 1000) note = it },
                textStyle = TextStyle(color = Color.White, fontSize = 15.sp),
                cursorBrush = SolidColor(BrandOrange),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        if (failed) {
            Text("Couldn’t send. Check your connection and try again.", fontSize = 13.sp, color = BrandOrange)
        }

        val enabled = reason != null && !sending
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(if (reason != null) BrandOrange else Color.White.copy(alpha = 0.1f))
                .clickable(enabled = enabled, role = Role.Button) {
                    val r = reason ?: return@clickable
                    sending = true
                    failed = false
                    scope.launch {
                        val ok = ContentReportService.submit(ctx, r, note)
                        sending = false
                        if (ok) sent = true else failed = true
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            if (sending) {
                CircularProgressIndicator(color = Color.Black, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
            } else {
                Text(
                    "Send report", fontSize = 16.sp, fontWeight = FontWeight.Bold,
                    color = if (reason != null) Color.Black else TextSecondary,
                )
            }
        }
        Spacer(Modifier.height(4.dp))
    }
}
