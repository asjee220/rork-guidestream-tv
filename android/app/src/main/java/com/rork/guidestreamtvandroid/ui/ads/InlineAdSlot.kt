package com.rork.guidestreamtvandroid.ui.ads

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.repository.RakutenManager
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger

/**
 * The eight affiliate offers shared across every inline ad surface.
 * Strings match the pool previously embedded in HomeScreen so historical
 * Watch Graph attribution stays comparable.
 */
val inlineAdPool: List<Triple<String, String, String>> = listOf(
    Triple("netflix", "Stream more on Netflix", "Unlimited shows & movies · Try free"),
    Triple("hbo", "Watch more on Max", "HBO, Max Originals & more · Try free"),
    Triple("hulu", "Live TV + streaming on Hulu", "Starting at $7.99/mo · Try free"),
    Triple("disney", "Disney+, Hulu & ESPN+ bundle", "Disney Bundle · Try free"),
    Triple("appletv", "Award-winning originals", "Apple TV+ · First month free"),
    Triple("prime", "Included with Prime", "Prime Video · Try free"),
    Triple("paramount", "NFL on CBS & live sports", "Paramount+ · Try free"),
    Triple("peacock", "Stream free on Peacock", "NBC shows & live sports · Free tier"),
)

/**
 * Shared inline ad slot — mirrors iOS InlineAdSlotView. Selects an offer by
 * slot index from the pool entries the user hasn't selected (hard filter),
 * and renders a SponsoredSlot with the appropriate adSource, sectionKey,
 * and preferredSource. When every pool service is owned the Rakuten card is
 * suppressed and the slot renders native-AdMob-only. The caller owns
 * dismissal state via the dismissed map.
 */
@Composable
fun InlineAdSlot(
    slotIndex: Int,
    selectedServices: Set<String>,
    adSource: String,
    sectionKey: String,
    dismissed: MutableMap<Int, Boolean>,
    onDismiss: () -> Unit = { dismissed[slotIndex] = true },
) {
    if (dismissed[slotIndex] == true) return

    val offer = selectOffer(slotIndex, selectedServices)
    val service = offer?.let { StreamingCatalog.service(it.first) }

    Box(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        SponsoredSlot(
            preferredSource = if (slotIndex % 2 == 0) PooledAdSource.ADMOB_FIRST else PooledAdSource.RAKUTEN_FIRST,
            service = service,
            serviceId = offer?.first ?: "",
            headline = offer?.second ?: "",
            subtitle = offer?.third ?: "",
            onDismiss = onDismiss,
            adSource = adSource,
            sectionKey = sectionKey,
            allowRakutenFallback = offer != null,
        )
    }
}

/**
 * Picks the affiliate offer for a slot from the pool entries the user
 * doesn't already subscribe to, rotating by slot index. Returns null when
 * every pool service is owned — the caller then suppresses the Rakuten
 * card instead of advertising an owned service.
 */
private fun selectOffer(
    slotIndex: Int,
    selectedServices: Set<String>,
): Triple<String, String, String>? {
    val unowned = inlineAdPool.filter { it.first !in selectedServices }
    if (unowned.isEmpty()) return null
    return unowned[slotIndex % unowned.size]
}
