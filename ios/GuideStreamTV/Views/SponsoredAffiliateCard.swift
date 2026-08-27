//
//  SponsoredAffiliateCard.swift
//  GuideStreamTV
//
//  Shared affiliate banner. In feed style it renders the 96pt inline chip —
//  72pt creative square, up to three lines of headline, an "advertiser ·
//  Sponsored" line, and a trailing close control. Renders a Rakuten "Stream more on…"
//  card with a branded service tile, headline, subtitle, "Sponsored · Rakuten"
//  footer — all on a see-through ultraThinMaterial + navy-tinted background
//  so the playing video/content behind remains visible. Used by the Reels
//  glass overlay, episode/creator detail sheets, and the sports watch sheet
//  so every surface shows the identical card.
//

import SwiftUI

struct SponsoredAffiliateCard: View {
    let service: StreamingService?
    let fallbackName: String
    let fallbackColor: Color
    let headline: String
    let subtitle: String
    let onTap: () -> Void
    let onDismiss: () -> Void
    var compact: Bool = false

    /// When true the card renders the compact 96pt inline-feed chip that
    /// matches NativeAdCardView's chip exactly — same height, surface, tile
    /// size, and CTA pill — so a late native fill upgrading this fallback
    /// causes no layout shift. Takes precedence over both existing bodies
    /// (the pooled detail-sheet slots pass compact=false but feedStyle=true,
    /// and their fallback must still match the 96pt native chip).
    var feedStyle: Bool = false

    /// Feed chip over live video (Reels): keeps the chip layout but restores
    /// the translucent glass surface so the trailer behind stays visible.
    /// Every other inline surface sits on a solid background, where the
    /// opaque elevated surface reads better.
    var feedChipGlass: Bool = false

    var body: some View {
        if feedStyle {
            feedChipBody
        } else if compact {
            compactBody
        } else {
            fullBody
        }
    }

    // MARK: - Full card (existing layout, unchanged)

    private var fullBody: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Brand tile — 40×40 rounded square
                brandTile

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .scaledFont(size: 10)
                        .foregroundStyle(Color.white.opacity(0.62))
                    Text("Sponsored · Rakuten")
                        .scaledFont(size: 9)
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial.opacity(0.67))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 8/255, green: 14/255, blue: 24/255).opacity(0.19))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.11), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 14, y: 4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compact chip (120pt tall, fills container width)

    private var compactBody: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                compactBrandTile
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .scaledFont(size: 13, weight: .heavy)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .scaledFont(size: 10)
                            .foregroundStyle(Color.white.opacity(0.62))
                            .lineLimit(3)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial.opacity(0.67))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 8/255, green: 14/255, blue: 24/255).opacity(0.19))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.11), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 14, y: 4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topLeading) {
                adMarker
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feed chip (96pt inline row — mirrors NativeAdCardView's chip)

    /// Compact inline-feed chip. Height, surface, creative square, attribution
    /// line, and the trailing close control all mirror the native ad chip so a
    /// late native fill upgrading this fallback causes no layout shift.
    private var feedChipBody: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    feedChipBrandTile
                    VStack(alignment: .leading, spacing: 5) {
                        Text(headline)
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 5) {
                            Text(service?.name ?? fallbackName)
                                .scaledFont(size: 11)
                                .foregroundStyle(Color.white.opacity(0.52))
                                .lineLimit(1)
                            feedChipAttribution
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                }
                // Trailing inset clears the close control so a three-line
                // headline never runs underneath it. No leading or vertical
                // inset — the creative runs edge to edge and the card's own
                // clip shape rounds its outer corners.
                .padding(.trailing, 44)
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .background(feedChipSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            // Close — layered above the card so its tap never opens the offer.
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    onDismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Color.white.opacity(0.55))
                    // 44pt target for the HIG minimum — the glyph still reads
                    // as a small X because the frame is transparent.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The chip's surface. Opaque elevated by default; translucent glass over
    /// live video, matching the card Reels showed before it adopted the chip.
    @ViewBuilder
    private var feedChipSurface: some View {
        if feedChipGlass {
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial.opacity(0.67))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 8/255, green: 14/255, blue: 24/255).opacity(0.19))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.11), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 14, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    /// Required attribution, sitting immediately after the advertiser name —
    /// the affiliate card is Rakuten inventory, so it reads "Sponsored" where
    /// the native chip reads "Ad".
    private var feedChipAttribution: some View {
        Text("Sponsored")
            .scaledFont(size: 10, weight: .medium)
            .foregroundStyle(Color.white.opacity(0.62))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.12))
            )
    }

    /// 96pt brand tile — a flush square filling the leading edge of the chip,
    /// matching the native chip's creative. Square-cornered on purpose: the
    /// card's clip shape rounds the two corners that meet its edges.
    private var feedChipBrandTile: some View {
        ZStack {
            Rectangle()
                .fill(service?.bg ?? Color.white.opacity(0.10))
                .frame(width: 96, height: 96)
            if let service {
                ServiceBrandContent(
                    display: service.display,
                    size: .mini(64)
                )
                .frame(width: 64, height: 64)
            } else {
                Text(String(fallbackName.prefix(3)).uppercased())
                    .scaledFont(size: 19, weight: .black)
                    .foregroundStyle(fallbackColor)
            }
        }
        .frame(width: 96, height: 96)
    }

    // MARK: - AD marker (compact only)

    private var adMarker: some View {
        Text("AD")
            .scaledFont(size: 7, weight: .heavy)
            .tracking(0.5)
            .foregroundStyle(Color.white.opacity(0.55))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.35))
            )
            .padding(.top, 3)
            .padding(.leading, 3)
            .allowsHitTesting(false)
    }

    // MARK: - Brand tile (full)

    private var brandTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(service?.bg ?? Color.white.opacity(0.10))
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
            if let service {
                ServiceBrandContent(
                    display: service.display,
                    size: .mini(32)
                )
                .frame(width: 32, height: 32)
            } else {
                Text(String(fallbackName.prefix(3)).uppercased())
                    .scaledFont(size: 11, weight: .black)
                    .foregroundStyle(fallbackColor)
            }
        }
        .frame(width: 40, height: 40)
    }

    // MARK: - Brand tile (compact)

    private var compactBrandTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(service?.bg ?? Color.white.opacity(0.10))
                .frame(width: 56, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
            if let service {
                ServiceBrandContent(
                    display: service.display,
                    size: .mini(44)
                )
                .frame(width: 44, height: 44)
            } else {
                Text(String(fallbackName.prefix(3)).uppercased())
                    .scaledFont(size: 14, weight: .black)
                    .foregroundStyle(fallbackColor)
            }
        }
        .frame(width: 56, height: 56)
    }
}
