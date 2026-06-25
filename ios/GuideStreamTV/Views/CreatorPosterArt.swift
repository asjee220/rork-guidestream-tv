//
//  CreatorPosterArt.swift
//  GuideStreamTV
//
//  Shared 2:3 poster art for non-TMDB creators (YouTube, Twitch, Kick, podcasts).
//  Replaces the crop-to-fill image with a composed card:
//    * branded gradient background
//    * creator image shown whole as a centred inset
//      – circle for people (YouTube, Twitch, Kick)
//      – rounded square for podcasts
//    * when image_url is nil, shows the source-type glyph instead
//
//  Call sites: EpisodeThumbCard (150×225), WatchListRow poster (60×90).
//

import SwiftUI

/// Composed poster art for non-TMDB creator entities.
/// Fills the given size with a branded gradient and shows the creator's image
/// as an inset — circle for streamers/channels, rounded square for podcasts.
struct CreatorPosterArt: View {
    let imageUrl: String?
    let kind: SourceKind
    let width: CGFloat
    let height: CGFloat
    let brandColor: Color

    /// Size of the inset image — 58 % of card width, clamped to a reasonable range.
    private var insetSize: CGFloat {
        max(24, width * 0.58)
    }

    /// Corner radius for the podcast rounded-square inset (~14 % of its side).
    private var podcastCornerRadius: CGFloat {
        insetSize * 0.14
    }

    /// Darkened / low-opacity variant of the brand color for the gradient tail.
    private var gradientTail: Color {
        brandColor.opacity(0.25)
    }

    var body: some View {
        ZStack {
            // Branded gradient background — fills the entire card.
            LinearGradient(
                colors: [brandColor.opacity(0.85), gradientTail],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Inset image or source glyph.
            if let url = imageUrl, !url.isEmpty {
                insetImageView(url: url)
            } else {
                sourceGlyph
                    .frame(width: insetSize, height: insetSize)
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Image inset

    @ViewBuilder
    private func insetImageView(url: String) -> some View {
        let shape: AnyShape = {
            if kind == .podcast {
                AnyShape(RoundedRectangle(cornerRadius: podcastCornerRadius, style: .continuous))
            } else {
                AnyShape(Circle())
            }
        }()

        RemoteImage(urlString: url, contentMode: .fill, fallbackColors: [brandColor, gradientTail])
            .frame(width: insetSize, height: insetSize)
            .clipShape(shape)
            .overlay {
                // Thin brand-colored ring for circle avatars (not podcasts).
                if kind != .podcast {
                    Circle()
                        .stroke(brandColor.opacity(0.5), lineWidth: 1.5)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    // MARK: - Source glyph (nil-image fallback)

    private var sourceGlyph: some View {
        Image(systemName: kind == .podcast ? "mic.fill" : "play.rectangle.fill")
            .font(.system(size: insetSize * 0.42, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
    }
}
