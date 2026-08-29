//
//  TVReelAdCarousel.swift
//  GuideStreamTVTV
//
//  The v2 inline ad chip and its carousel, ported to tvOS for Reels.
//
//  The chip is the shared v2 layout verbatim, only scaled: creative square
//  flush to the leading edge and the full height of the card, a three-line
//  semibold headline, the advertiser name followed by a muted `Ad` chip, no
//  CTA pill because the whole card is the target, dismiss top-trailing and
//  AdChoices bottom-trailing. Surface is glass rather than elevated —
//  the same rule Reels follows on iPhone and Android, because a trailer is
//  playing behind it. `TVSponsoredChip` keeps the opaque surface and stays
//  as it is on Home.
//
//  Cadence matches mobile: eight pages, page 0 and pages 3 and 6 are always
//  an affiliate offer, pages 1, 2, 4, 5 and 7 would try a native ad first.
//  There is no native ad inventory on tvOS — Google Mobile Ads has no tvOS
//  SDK — so those pages always take the Rakuten backfill. The page shape is
//  kept so the two platforms stay comparable in reporting.
//

import SwiftUI

struct TVReelAdCarousel: View {
    let titleName: String
    let titleId: String
    /// Provider the reel's own title streams on, excluded from the pool.
    let providerName: String?
    /// Drives the rotation offset so different titles lead with different
    /// services, the same as `abs(tmdbId) % eligible.count` on the phone.
    let tmdbId: Int
    @Binding var isDismissed: Bool
    var isFocusedChip: Bool
    var isFocusedDismiss: Bool
    /// Incremented by the screen when the chip is selected. The carousel
    /// owns the current page, so it opens the offer.
    var selectSignal: Int

    @State private var page: Int = 0
    @State private var advanceTask: Task<Void, Never>?
    @State private var loggedPages: Set<Int> = []

    private static let pageCount = 8
    /// Pages that would carry a native ad on mobile. Kept for parity.
    private static let nativeFirstPages: Set<Int> = [1, 2, 4, 5, 7]
    private static let advanceSeconds: Double = 5.5

    private var pool: [TVAffiliateService.Advertiser] {
        TVAffiliateService.shared.gapAdvertisers(excluding: providerName)
    }

    private var current: TVAffiliateService.Advertiser? {
        let pool = pool
        guard !pool.isEmpty else { return nil }
        let start = abs(tmdbId) % pool.count
        return pool[(start + page) % pool.count]
    }

    var body: some View {
        // Nothing eligible means no carousel at all, exactly as on mobile.
        if !isDismissed, let advertiser = current {
            VStack(alignment: .leading, spacing: 14) {
                chip(for: advertiser)
                dots
            }
            .onAppear { arm() }
            .onDisappear { advanceTask?.cancel() }
            .onChange(of: page) { _, _ in logImpression(for: advertiser) }
            .onChange(of: selectSignal) { _, _ in openOffer() }
        }
    }

    // MARK: - Chip

    private func chip(for advertiser: TVAffiliateService.Advertiser) -> some View {
        HStack(spacing: 0) {
            // Creative: square, flush to the leading edge, full height.
            ZStack {
                TVTheme.blue.opacity(0.18)
                Text(Self.initials(advertiser.displayName))
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 192, height: 192)

            VStack(alignment: .leading, spacing: 10) {
                Text(headline(for: advertiser))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(TVTheme.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 10) {
                    Text(advertiser.displayName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(TVTheme.textSecondary)
                    Text("Ad")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(.horizontal, 26)

            Spacer(minLength: 0)
        }
        .frame(height: 192)
        .frame(maxWidth: 900, alignment: .leading)
        .background(Color(red: 0x12 / 255, green: 0x1B / 255, blue: 0x2A / 255).opacity(0.19))
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 20))
        .overlay(alignment: .topTrailing) { dismissControl }
        .overlay(alignment: .bottomTrailing) {
            Text("•••")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.trailing, 22)
                .padding(.bottom, 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isFocusedChip ? TVTheme.blue.opacity(0.9) : Color.white.opacity(0.11),
                    lineWidth: isFocusedChip ? 3 : 1
                )
        }
        .scaleEffect(isFocusedChip ? 1.03 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isFocusedChip)
    }

    private var dismissControl: some View {
        Image(systemName: "xmark")
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(Color.white.opacity(isFocusedDismiss ? 1.0 : 0.72))
            .frame(width: 88, height: 88)
            .background(
                Circle()
                    .fill(Color.white.opacity(isFocusedDismiss ? 0.20 : 0))
                    .padding(18)
            )
    }

    private var dots: some View {
        HStack(spacing: 11) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                Circle()
                    .fill(index == page ? TVTheme.orange : Color.white.opacity(0.28))
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.leading, 4)
        .animation(.easeInOut(duration: 0.25), value: page)
    }

    // MARK: - Behaviour

    private func headline(for advertiser: TVAffiliateService.Advertiser) -> String {
        Self.nativeFirstPages.contains(page)
            ? "Stream thousands of hit movies and shows on \(advertiser.displayName), on any screen you own."
            : "Watch \(titleName) and more on \(advertiser.displayName) — start your subscription today."
    }

    private func arm() {
        advanceTask?.cancel()
        if let advertiser = current { logImpression(for: advertiser) }
        advanceTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.advanceSeconds))
                guard !Task.isCancelled, !isDismissed else { return }
                page = (page + 1) % Self.pageCount
            }
        }
    }

    private func logImpression(for advertiser: TVAffiliateService.Advertiser) {
        guard !loggedPages.contains(page) else { return }
        loggedPages.insert(page)
        WatchIntentLogger.shared.log(
            eventType: .adImpression,
            titleId: titleId,
            platformId: advertiser.key,
            metadata: [
                "source": "reel_ad_carousel",
                "position": page,
                "show_platform": providerName ?? "unknown"
            ]
        )
    }

    private func openOffer() {
        guard let advertiser = current else { return }
        WatchIntentLogger.shared.log(
            eventType: .affiliateLinkTapped,
            titleId: titleId,
            platformId: advertiser.key,
            metadata: [
                "source": "reel_ad_carousel",
                "show_platform": providerName ?? "unknown"
            ]
        )
        guard let url = advertiser.appStoreURL else { return }
        TVOSDeepLinker.openAppStore(itmsURL: url) { _ in }
    }

    private static func initials(_ name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
