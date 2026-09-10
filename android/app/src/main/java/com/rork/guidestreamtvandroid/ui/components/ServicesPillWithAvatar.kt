package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
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
 * Home, Sports and the Watchlist all use it, so the pair cannot drift between
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
    /**
     * Modifier applied to the drawn 32dp ring — not to the 48dp hit target.
     * Home passes the coach-mark measurement here so the tour can point at the
     * profile in its new home; measuring the hit target instead drew a
     * spotlight circle noticeably larger than the avatar. Sports and the
     * Watchlist pass nothing, because only Home runs the tour.
     */
    avatarModifier: Modifier = Modifier,
) {
    val authVm = AuthViewModel.get()
    val selectedServices by authVm.selectedServices.collectAsStateWithLifecycle()
    val avatarUrl by authVm.accountAvatarUrl.collectAsStateWithLifecycle()
    val firstName by authVm.firstName.collectAsStateWithLifecycle()
    val lastName by authVm.lastName.collectAsStateWithLifecycle()
    val displayName by authVm.displayName.collectAsStateWithLifecycle()

    val serviceIds = StreamingCatalog.ordered(selectedServices).map { it.id }
    // GUI-101: shown even with nothing selected. The pill has its own empty
    // state; hiding it here was what left a viewer who skipped the onboarding
    // step with no route to the services editor.
    ServicesPill(
        serviceIds = serviceIds,
        onTap = onServicesTap,
        modifier = servicesPillModifier,
    )

    // The pill and the avatar are different controls and shouldn't look joined.
    Spacer(Modifier.width(AVATAR_GAP))

    // The clickable goes on a 48dp box, not on the 32dp avatar. Material's
    // minimum touch target is 48dp and the avatar sits at the very corner of
    // the screen; hanging the click on the drawn circle alone made it fiddly
    // to hit. Nothing drawn changes — the ring is still 32.
    Box(
        modifier = Modifier
            .size(AVATAR_HIT_TARGET)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onProfileTap() },
        contentAlignment = Alignment.Center,
    ) {
        UserAvatar(
            modifier = avatarModifier,
            initials = computeInitials(
                firstName = firstName,
                lastName = lastName,
                displayName = displayName,
                isGuest = authVm.isGuest.value,
                isAuthenticated = authVm.isAuthenticated.value,
            ),
            avatarUrl = avatarUrl,
            size = AVATAR_DIAMETER,
        )
    }
}

/**
 * Matches the services pill's height exactly: 22dp icons with 5dp of padding
 * above and below. The avatar is the pill's visual partner, so the two read as
 * one control group rather than two sizes.
 */
private val AVATAR_DIAMETER = 32.dp

/** Breathing room between the pill and the avatar. */
private val AVATAR_GAP = 18.dp

/** Material's minimum touch target, applied around the smaller drawn ring. */
private val AVATAR_HIT_TARGET = 48.dp
