//
//  HouseSlotCard.swift
//  GuideStreamTV
//
//  Last-resort fill for a sponsored slot: a house card promoting the app's
//  own features.
//
//  WHY THIS EXISTS. A slot picks an affiliate offer from a pool of eight
//  services, filtered to the ones the viewer does NOT already subscribe to —
//  the app must never advertise something they already pay for. A viewer who
//  subscribes to all eight therefore had no eligible offer anywhere, and the
//  slot fell through to `allowRakutenFallback == false`, whose only remaining
//  content was an AdMob native ad. On an AdMob miss the slot collapsed to zero
//  height, so the most engaged users saw nothing in any slot in the entire app
//  and it read as "advertising is broken".
//
//  A house card keeps the promise (never advertise an owned service) without
//  the dead space. It is the LAST resort: an eligible affiliate offer wins,
//  and a native ad still upgrades the slot the moment one lands in the pool.
//

import SwiftUI

struct HouseSlotCard: View {
    struct Offer {
        let icon: String
        let headline: String
        let subtitle: String
    }

    let offer: Offer
    var compact: Bool = false
    var feedStyle: Bool = false
    var onDismiss: () -> Void

    /// House offers describe things the app already does, so none of them can
    /// promise something a viewer cannot find.
    private static let pool: [Offer] = [
        Offer(icon: "square.stack.3d.up.fill",
              headline: "One watchlist, every service",
              subtitle: "Save a show once and see it wherever you watch"),
        Offer(icon: "bell.badge.fill",
              headline: "Never miss a premiere",
              subtitle: "Get told the day a new episode lands"),
        Offer(icon: "sportscourt.fill",
              headline: "Follow your teams",
              subtitle: "Live scores and where the game is on"),
        Offer(icon: "sparkles.tv.fill",
              headline: "Watch on the big screen",
              subtitle: "GuideStream TV is on Apple TV too")
    ]

    static func offer(for seed: Int) -> Offer {
        pool[abs(seed) % pool.count]
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.16))
                .frame(width: iconPlate, height: iconPlate)
                .overlay(
                    Image(systemName: offer.icon)
                        .scaledFont(size: iconPlate * 0.46, weight: .semibold)
                        .foregroundStyle(Color.orange)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(offer.headline)
                    .scaledFont(size: compact ? 13 : 14, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(offer.subtitle)
                    .scaledFont(size: compact ? 11 : 12, weight: .regular)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .scaledFont(size: 10, weight: .bold)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .frame(height: cardHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(offer.headline). \(offer.subtitle)")
    }

    /// Matches the 96pt inline chip row and the taller detail-sheet card, so
    /// swapping in a native ad causes no layout jump.
    private var cardHeight: CGFloat { compact && feedStyle ? 96 : 84 }
    private var iconPlate: CGFloat { compact && feedStyle ? 56 : 44 }
}

#Preview("House slot") {
    ZStack {
        Color.navy.ignoresSafeArea()
        VStack(spacing: 16) {
            HouseSlotCard(offer: HouseSlotCard.offer(for: 0), compact: true, feedStyle: true, onDismiss: {})
            HouseSlotCard(offer: HouseSlotCard.offer(for: 1), onDismiss: {})
        }
        .padding()
    }
}
