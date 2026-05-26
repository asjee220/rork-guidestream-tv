//
//  HomeHeroCarousel.swift
//  GuideStreamTV
//
//  Replaces the static hero card on Home with a peek-style horizontal
//  carousel of large tiles. The rail mixes the most popular trending shows
//  and movies with the most relevant live or upcoming sports broadcasts so
//  the home feed leads with whatever's biggest right now.
//
//  Each tile renders its own outlined Play CTA — orange for movies/shows
//  (presents EpisodeDetailSheet) and blue for sports (presents
//  SportsWatchSheet). Tapping anywhere on the card invokes the same action
//  so the entire tile is one large hit target.
//

import SwiftUI
import UIKit

/// Heterogeneous item used by the hero carousel. Media items carry an
/// optional pre-resolved streaming platform so the badge can show the real
/// service (Netflix, HBO, etc.) without a per-card network call.
enum HeroItem: Identifiable {
    case media(TMDBResult, Platform?)
    case game(SportsGame)
    case news(NewsStream)

    var id: String {
        switch self {
        case .media(let r, _): return "media-\(r.id)"
        case .game(let g): return "game-\(g.id)"
        case .news(let n): return "news-\(n.id)"
        }
    }
}

struct HomeHeroCarousel: View {
    let items: [HeroItem]
    let onSelectMedia: (TMDBResult, Platform?) -> Void
    let onSelectGame: (SportsGame) -> Void
    let onSelectNews: (NewsStream) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(items) { item in
                    HeroCarouselCard(item: item) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        switch item {
                        case .media(let result, let platform):
                            onSelectMedia(result, platform)
                        case .game(let game):
                            onSelectGame(game)
                        case .news(let news):
                            onSelectNews(news)
                        }
                    }
                    .containerRelativeFrame(.horizontal) { length, _ in
                        // Slightly narrower than the container so the next
                        // card peeks ~26pt past the right edge.
                        max(length - 60, 240)
                    }
                    .scrollTransition(.interactive) { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.78)
                            .scaleEffect(phase.isIdentity ? 1 : 0.96)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .frame(height: 250)
    }
}

// MARK: - Card

private struct HeroCarouselCard: View {
    let item: HeroItem
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            ZStack {
                backdrop

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.10),
                        Color.black.opacity(0.45),
                        Color.black.opacity(0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                content
                    .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(HeroCarouselButtonStyle())
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 18))
        .shadow(color: glowColor, radius: 24, y: 12)
    }

    private var strokeColor: Color {
        switch item {
        case .media: return Color.orange.opacity(0.30)
        case .game: return Color.blue.opacity(0.40)
        // News stroke matches the CTA tint, the same way media uses orange
        // and sports uses blue — the rim glow is what carries the rail's
        // semantic color, not the backdrop itself.
        case .news: return Color.newsGreen.opacity(0.45)
        }
    }

    private var glowColor: Color {
        switch item {
        case .media: return Color.orange.opacity(0.18)
        case .game: return Color.blue.opacity(0.24)
        case .news: return Color.newsGreen.opacity(0.30)
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        switch item {
        case .media(let result, _): mediaBackdrop(result)
        case .game(let game): sportsBackdrop(game)
        case .news(let news): newsBackdrop(news)
        }
    }

    /// News tile backdrop — matches the media tile's full-bleed image
    /// treatment so the rail reads as a single carousel. When the image
    /// fails to load the fallback gradient is news-brand green so the card
    /// still feels on-rail; otherwise the show's backdrop carries the
    /// imagery just like a movie/series tile.
    private func newsBackdrop(_ news: NewsStream) -> some View {
        Color.black
            .overlay {
                RemoteImage(
                    urlString: news.backdropUrl ?? news.posterUrl,
                    contentMode: .fill,
                    fallbackColors: [
                        Color.newsGreen.opacity(0.85),
                        Color(red: 0.04, green: 0.20, blue: 0.18)
                    ]
                )
                .allowsHitTesting(false)
            }
    }

    private func mediaBackdrop(_ result: TMDBResult) -> some View {
        Color.black
            .overlay {
                RemoteImage(
                    urlString: result.backdropUrl ?? result.posterUrl,
                    contentMode: .fill,
                    fallbackColors: [
                        Color(red: 0.15, green: 0.05, blue: 0.20),
                        Color(red: 0.04, green: 0.04, blue: 0.10)
                    ]
                )
                .allowsHitTesting(false)
            }
    }

    private func sportsBackdrop(_ game: SportsGame) -> some View {
        let awayC = game.away.primaryHex.map { Color(hex: $0) } ?? Color(red: 0.10, green: 0.15, blue: 0.32)
        let homeC = game.home.primaryHex.map { Color(hex: $0) } ?? Color(red: 0.32, green: 0.10, blue: 0.15)
        return ZStack {
            LinearGradient(
                colors: [awayC, awayC.opacity(0.85), homeC.opacity(0.85), homeC],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Translucent team abbreviation watermarks for depth.
            HStack {
                Text(game.away.abbreviation)
                    .scaledFont(size: 112, weight: .black)
                    .foregroundStyle(.white.opacity(0.10))
                    .offset(x: -8, y: -22)
                Spacer()
                Text(game.home.abbreviation)
                    .scaledFont(size: 112, weight: .black)
                    .foregroundStyle(.white.opacity(0.10))
                    .offset(x: 8, y: 22)
            }
            .padding(.horizontal, 4)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case .media(let result, let platform): mediaContent(result, platform)
        case .game(let game): gameContent(game)
        case .news(let news): newsContent(news)
        }
    }

    // MARK: - News content

    private func newsContent(_ news: NewsStream) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                breakingNewsBadge
                badgePill(news.outlet.uppercased(), bg: Color.white.opacity(0.20))
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text(news.title)
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: Color.black.opacity(0.45), radius: 8, y: 2)

                newsMetaRow(news)

                ctaPill(label: "Watch Now", tint: Color.newsGreen)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pulsing "BREAKING NEWS" pill — uses a `symbolEffect` so it gently
    /// breathes rather than aggressively flashing, matching Apple News'
    /// own "top stories" treatment.
    private var breakingNewsBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .scaledFont(size: 10, weight: .black)
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
            Text("BREAKING")
                .scaledFont(size: 10, weight: .black)
                .tracking(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.18)))
        .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
    }

    private func newsMetaRow(_ news: NewsStream) -> some View {
        HStack(spacing: 8) {
            Text(news.isTV ? "News Show" : "News Special")
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.85))
            if let date = news.publishedAt {
                metaDot
                Text(Self.relativeDate(date))
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            if let provider = news.providerName {
                metaDot
                Text(provider)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private static func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Media content

    private func mediaContent(_ result: TMDBResult, _ platform: Platform?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                badgePill("TRENDING", bg: Color.orange)
                if let platform {
                    badgePill(platform.name, bg: platform.color)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text(result.displayName)
                    .scaledFont(size: 26, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: Color.black.opacity(0.45), radius: 8, y: 2)

                mediaMetaRow(result)

                ctaPill(label: "Play", tint: Color.orange)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mediaMetaRow(_ result: TMDBResult) -> some View {
        HStack(spacing: 8) {
            Text(result.isTV ? "Series" : "Movie")
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.75))
            if let year = result.year {
                metaDot
                Text("\(year)")
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            if let rating = result.voteAverage, rating > 0 {
                metaDot
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .scaledFont(size: 10)
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.24))
                    Text(String(format: "%.1f", rating))
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(.white)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Game content

    private func gameContent(_ game: SportsGame) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                statusBadge(game)
                badgePill(game.sport.uppercased(), bg: Color.white.opacity(0.18))
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(game.away.shortName) vs \(game.home.shortName)")
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: Color.black.opacity(0.45), radius: 8, y: 2)

                sportsMetaRow(game)

                ctaPill(label: ctaLabel(for: game), tint: Color.blue)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ctaLabel(for game: SportsGame) -> String {
        switch game.state {
        case .live: return "Watch Live"
        case .pre: return "View Game"
        case .post: return "Watch Recap"
        }
    }

    private func sportsMetaRow(_ game: SportsGame) -> some View {
        HStack(spacing: 8) {
            if game.state != .pre {
                HStack(spacing: 6) {
                    Text(game.away.abbreviation)
                        .scaledFont(size: 11, weight: .heavy)
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text(game.away.score)
                        .scaledFont(size: 16, weight: .black)
                        .foregroundStyle(.white)
                    Text("–")
                        .scaledFont(size: 13, weight: .bold)
                        .foregroundStyle(Color.white.opacity(0.4))
                    Text(game.home.score)
                        .scaledFont(size: 16, weight: .black)
                        .foregroundStyle(.white)
                    Text(game.home.abbreviation)
                        .scaledFont(size: 11, weight: .heavy)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                metaDot
            }
            Text(game.statusDetail)
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func statusBadge(_ game: SportsGame) -> some View {
        switch game.state {
        case .live:
            HStack(spacing: 5) {
                Circle().fill(.white).frame(width: 6, height: 6)
                Text("LIVE")
                    .scaledFont(size: 10, weight: .black)
                    .tracking(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255)))
        case .pre:
            badgePill("UPCOMING", bg: Color.orange)
        case .post:
            badgePill("FINAL", bg: Color.white.opacity(0.20))
        }
    }

    // MARK: - Building blocks

    private var metaDot: some View {
        Text("·")
            .scaledFont(size: 12, weight: .bold)
            .foregroundStyle(Color.white.opacity(0.4))
    }

    private func badgePill(_ text: String, bg: Color) -> some View {
        Text(text)
            .scaledFont(size: 10, weight: .black)
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(bg))
    }

    /// Outlined call-to-action pill. Outline color (orange or blue) carries
    /// the semantic meaning — orange for movies/shows, blue for sports.
    private func ctaPill(label: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
                .scaledFont(size: 12, weight: .bold)
            Text(label)
                .scaledFont(size: 14, weight: .bold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.35))
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(
            Capsule().stroke(tint, lineWidth: 1.5)
        )
        .shadow(color: tint.opacity(0.30), radius: 12, y: 4)
    }
}

// MARK: - Button style

private struct HeroCarouselButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
