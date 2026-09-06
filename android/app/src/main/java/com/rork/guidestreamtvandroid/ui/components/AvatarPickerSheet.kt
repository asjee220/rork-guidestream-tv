package com.rork.guidestreamtvandroid.ui.components

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.SheetLevel
import com.rork.guidestreamtvandroid.ui.theme.SheetSurfaceBase
import com.rork.guidestreamtvandroid.ui.theme.sheetTopInset
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/**
 * Lets a signed-in viewer change the picture in their profile header: upload
 * one from the photo library, pick one of the built-in presets, or clear back
 * to the initials monogram. Mirrors the iOS AvatarPickerSheet.
 *
 * Guests get the presets but not the upload. `users.avatar_url` is keyed on the
 * auth uuid and the avatars bucket's RLS policies scope writes to
 * `avatars/<auth.uid()>/…`, so there is nowhere for a guest's file to go and
 * nothing to attach it to — offering the button and failing at the end would be
 * worse than not offering it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AvatarPickerSheet(
    initials: String,
    onDismiss: () -> Unit,
) {
    val authVm = AuthViewModel.get()
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val avatarUrl by authVm.accountAvatarUrl.collectAsStateWithLifecycle()

    var isUploading by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var pickedUri by remember { mutableStateOf<Uri?>(null) }

    val picker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri -> pickedUri = uri }

    LaunchedEffect(pickedUri) {
        val uri = pickedUri ?: return@LaunchedEffect
        isUploading = true
        errorText = null
        val bytes = withContext(Dispatchers.IO) {
            // Downscale before upload. A modern phone photo is several
            // megabytes and the avatars bucket caps objects at 5 MB, so
            // sending the original would fail for exactly the people most
            // likely to try it. 512px is comfortably more than the 88dp the
            // largest avatar draws at.
            runCatching {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    val decoded = BitmapFactory.decodeStream(input) ?: return@use null
                    val longest = maxOf(decoded.width, decoded.height).toFloat()
                    val scale = if (longest > 512f) 512f / longest else 1f
                    val resized: Bitmap = Bitmap.createScaledBitmap(
                        decoded,
                        (decoded.width * scale).toInt().coerceAtLeast(1),
                        (decoded.height * scale).toInt().coerceAtLeast(1),
                        true,
                    )
                    ByteArrayOutputStream().use { out ->
                        resized.compress(Bitmap.CompressFormat.JPEG, 85, out)
                        out.toByteArray()
                    }
                }
            }.getOrNull()
        }
        if (bytes == null) {
            errorText = "That image couldn't be read."
        } else if (authVm.uploadAvatar(bytes) == null) {
            errorText = "Upload failed. Check your connection and try again."
        }
        isUploading = false
        pickedUri = null
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = SheetSurfaceBase,
        scrimColor = Color.Black.copy(alpha = 0.60f),
        tonalElevation = 0.dp,
        dragHandle = { GsSheetDragHandle(level = SheetLevel.Base) },
        contentWindowInsets = { sheetTopInset() },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = "Profile Picture",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Start,
            )
            Spacer(Modifier.height(18.dp))

            Box(contentAlignment = Alignment.Center) {
                UserAvatar(initials = initials, avatarUrl = avatarUrl, size = 96.dp)
                if (isUploading) {
                    CircularProgressIndicator(color = BrandOrange, modifier = Modifier.size(36.dp))
                }
            }

            Spacer(Modifier.height(20.dp))

            if (authVm.isAuthenticated.value) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp)
                        .clip(RoundedCornerShape(25.dp))
                        .background(BrandOrange)
                        .clickable(
                            enabled = !isUploading,
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) {
                            picker.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                            )
                        },
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Filled.PhotoLibrary,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = "Upload a photo",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White,
                    )
                }
                Spacer(Modifier.height(22.dp))
            }

            Text(
                text = "Or pick one",
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextSecondary,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Start,
            )
            Spacer(Modifier.height(12.dp))

            LazyVerticalGrid(
                columns = GridCells.Fixed(4),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.height(150.dp),
            ) {
                items(AvatarPreset.all) { preset ->
                    Box(contentAlignment = Alignment.Center) {
                        UserAvatar(
                            initials = initials,
                            avatarUrl = preset.storageValue,
                            size = 56.dp,
                            modifier = Modifier.clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { authVm.setAvatar(preset.storageValue) },
                        )
                        if (avatarUrl == preset.storageValue) {
                            Box(
                                modifier = Modifier
                                    .size(62.dp)
                                    .clip(CircleShape)
                                    .border(3.dp, BrandOrange, CircleShape),
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(16.dp))
            Text(
                text = "Use my initials",
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextSecondary,
                modifier = Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { authVm.setAvatar(null) },
            )

            errorText?.let {
                Spacer(Modifier.height(12.dp))
                Text(
                    text = it,
                    fontSize = 12.sp,
                    color = Color(0xFFEF4444),
                    textAlign = TextAlign.Center,
                )
            }

            Spacer(Modifier.height(24.dp))
        }
    }
}
