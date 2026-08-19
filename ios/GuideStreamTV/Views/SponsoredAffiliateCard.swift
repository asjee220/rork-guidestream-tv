//
//  SponsoredAffiliateCard.swift
//  GuideStreamTV
//
//  Shared frosted-glass affiliate banner with thinned frost layer. Renders a Rakuten "Stream more on…"
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

    /// When true the card renders the compact 88pt inline-feed chip that
    /// matches NativeAdCardView's chip exactly — same height, surface, tile
    /// size, and CTA pill — so a late native fill upgrading this fallback
    /// causes no layout shift. Takes precedence over both existing bodies
    /// (the pooled detail-sheet slots pass compact=false but feedStyle=true,
    /// and their fallback must still match the 88pt native chip).
    var feedStyle: Bool = false

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

    // MARK: - Feed chip (88pt inline row — mirrors NativeAdCardView's chip)

    /// Compact inline-feed chip. Height, surface, tile size, and CTA pill all
    /// mirror the native ad chip so the fallback→native upgrade is seamless.
    private var feedChipBody: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                feedChipBrandTile
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .scaledFont(size: 13, weight: .heavy)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Text("Sponsored · Rakuten")
                        .scaledFont(size: 9.5)
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                feedChipPill
            }
            .padding(12)
            .frame(height: 88)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// 60pt brand tile — matches the native chip's icon square.
    private var feedChipBrandTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(service?.bg ?? Color.white.opacity(0.10))
                .frame(width: 60, height: 60)
            if let service {
                ServiceBrandContent(
                    display: service.display,
                    size: .mini(48)
                )
                .frame(width: 48, height: 48)
            } else {
                Text(String(fallbackName.prefix(3)).uppercased())
                    .scaledFont(size: 15, weight: .black)
                    .foregroundStyle(fallbackColor)
            }
        }
        .frame(width: 60, height: 60)
    }

    /// Trailing "Get offer" pill — matches the native chip's CTA.
    private var feedChipPill: some View {
        Text("Get offer")
            .scaledFont(size: 11, weight: .bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange)
            )
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
