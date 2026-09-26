//
//  TVSponsoredChip.swift
//  GuideStreamTVTV
//
//  Focusable sponsored card that surfaces a gap-service advertiser for an
//  on-screen title. Shows the title name, the advertiser's display name,
//  and a "View in App Store" call-to-action. Selecting the chip opens the
//  tvOS App Store product page via `TVOSDeepLinker.openAppStore`.
//
//  The chip logs `ad_impression` once per appearance (deduplicated by the
//  parent view) and `affiliate_link_tapped` on select. Both calls no-op
//  for guests and signed-out viewers — `WatchIntentLogger` handles that.
//

import SwiftUI

/// Resolved sponsored-chip payload: the advertiser, the on-screen title
/// it was resolved from, and the provider name that matched. Used to
/// deduplicate impressions and prevent two chips for the same advertiser
/// on one screen.
struct SponsoredChipData: Identifiable, Hashable {
    let advertiser: TVAffiliateService.Advertiser
    let titleName: String
    let titleId: String?
    let providerName: String?
    let surface: String
    var id: String { advertiser.key }
}

struct TVSponsoredChip: View {
    let data: SponsoredChipData

    @FocusState private var isFocused: Bool
    @State private var hasLoggedImpression = false

    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack(spacing: 20) {
                // Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isFocused ? Color.black.opacity(0.08) : TVTheme.blue.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "app.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(isFocused ? TVButtonFocus.content : TVTheme.blue)
                }

                // Text block: SPONSORED marker, headline, second line
                VStack(alignment: .leading, spacing: 4) {
                    Text("SPONSORED")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(isFocused ? TVButtonFocus.content.opacity(0.6) : TVTheme.textTertiary)
                        .tracking(1.5)
                    Text("\(data.titleName) is on \(data.advertiser.displayName)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isFocused ? TVButtonFocus.content : TVTheme.textPrimary)
                        .lineLimit(1)
                    Text("You don't have \(data.advertiser.displayName) yet — get the app on Apple TV")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isFocused ? TVButtonFocus.content.opacity(0.75) : TVTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Trailing CTA
                HStack(spacing: 6) {
                    Text("View in App Store")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isFocused ? TVButtonFocus.content : TVTheme.blue)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isFocused ? TVButtonFocus.content : TVTheme.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .background(isFocused ? TVButtonFocus.fill : TVTheme.surface)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isFocused ? Color.clear : TVTheme.hairline, lineWidth: 1)
            }
            // The chip is as wide as its rail, so it lifts a little less
            // than a pill does; the shadow replaces the card style's own.
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .tvButtonFocusShadow(isFocused)
        }
        // The chip reads as a button, so it takes the shared white-fill
        // focus instead of the card style's lift and sheen.
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { logImpression() }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isFocused)
    }

    // MARK: - Tap handling

    private func handleTap() {
        let url = data.advertiser.appStoreURL

        if let url {
            TVOSDeepLinker.openAppStore(itmsURL: url) { opened in
                logTap(opened: opened)
            }
        } else {
            logTap(opened: false)
        }
    }

    private func logImpression() {
        guard !hasLoggedImpression else { return }
        hasLoggedImpression = true
        WatchIntentLogger.shared.log(
            eventType: .adImpression,
            titleId: data.titleId,
            platformId: data.providerName,
            metadata: [
                "advertiser_key": data.advertiser.key,
                "provider_name": data.providerName ?? "",
                "title_id": data.titleId ?? "",
                "title_name": data.titleName,
                "surface": data.surface
            ]
        )
    }

    private func logTap(opened: Bool) {
        WatchIntentLogger.shared.log(
            eventType: .affiliateLinkTapped,
            titleId: data.titleId,
            platformId: data.providerName,
            metadata: [
                "advertiser_key": data.advertiser.key,
                "provider_name": data.providerName ?? "",
                "title_id": data.titleId ?? "",
                "title_name": data.titleName,
                "surface": data.surface,
                "opened": opened
            ]
        )
    }
}
