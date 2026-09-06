package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.ui.profile.computeInitials

/**
 * The trailing half of the top bar: the services pill and the profile avatar,
 * in that order, as one unit.
 *
 * Home, Sports and the Watch List all use it, so the pair cannot drift between
 * them the way it did when Sports kept its own copy of the pill and never got
 * the avatar.
 *
 * The avatar reads the account itself rather than taking it as a parameter —
 * there is exactly one signed-in viewer, and threading their avatar through
 * three screens' state buys nothing.
 */
@Composable
fun RowScope.ServicesPillWithAvatar(
    onServicesTap: () -> Unit,
    onProfileTap: () -> Unit,
    servicesPillModifier: Modifier = Modifier,
) {
    val authVm = AuthViewModel.get()
    val selectedServices by authVm.selectedServices.collectAsStateWithLifecycle()
    val avatarUrl by authVm.accountAvatarUrl.collectAsStateWithLifecycle()
    val firstName by authVm.firstName.collectAsStateWithLifecycle()
    val lastName by authVm.lastName.collectAsStateWithLifecycle()
    val displayName by authVm.displayName.collectAsStateWithLifecycle()

    val serviceIds = StreamingCatalog.ordered(selectedServices).map { it.id }
    if (serviceIds.isNotEmpty()) {
        ServicesPill(
            serviceIds = serviceIds,
            onTap = onServicesTap,
            modifier = servicesPillModifier,
        )
    }

    // The pill and the avatar are different controls and shouldn't look joined.
    Spacer(Modifier.width(AVATAR_GAP))

    UserAvatar(
        initials = computeInitials(
            firstName = firstName,
            lastName = lastName,
            displayName = displayName,
            isGuest = authVm.isGuest.value,
            isAuthenticated = authVm.isAuthenticated.value,
        ),
        avatarUrl = avatarUrl,
        size = AVATAR_DIAMETER,
        modifier = Modifier.clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
        ) { onProfileTap() },
    )
}

/**
 * Matches the services pill's height exactly: 22dp icons with 5dp of padding
 * above and below. The avatar is the pill's visual partner, so the two read as
 * one control group rather than two sizes.
 */
private val AVATAR_DIAMETER = 32.dp

/** Breathing room between the pill and the avatar. */
private val AVATAR_GAP = 18.dp
