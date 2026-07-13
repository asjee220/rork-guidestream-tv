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

/// Lightweight value type for a followed creator who is currently live.
/// Built from the customer's own user_streams rows joined with live_status,
/// so only creators the signed-in customer follows can appear in the hero rail.
struct HeroLiveCreator: Identifiable, Hashable {
    let titleId: String
    let displayName: String
    let avatarUrl: String?
    let streamTitle: String?
    let category: String?
    let viewerCount: Int?
    let startedAt: Date?
    let kind: SourceKind
    var id: String { titleId }
}

/// Heterogeneous item used by the hero carousel. Media items carry an
/// optional pre-resolved streaming platform so the badge can show the real
/// service (Netflix, HBO, etc.) without a per-card network call.
enum HeroItem: Identifiable {
    case media(TMDBResult, Platform?)
    case game(SportsGame)
    case liveCreator(HeroLiveCreator)
    case creatorUpload(NewEpisodeRow)

    var id: String {
        switch self {
        case .media(let r, _): return "media-\(r.id)"
        case .game(let g): return "game-\(g.id)"
        case .liveCreator(let c): return "live-\(c.titleId)"
        case .creatorUpload(let u): return "upload-\(u.id)"
        }
    }

    /// Returns the most-recent timestamp for sorting every tile newest-first.
    var sortDate: Date {
        switch self {
        case .media(let r, _):
            let raw = r.firstAirDate ?? r.releaseDate
            guard let raw, !raw.isEmpty else { return .distantPast }
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            return fmt.date(from: raw) ?? .distantPast
        case .game(let g):
            return g.startDate
        case .liveCreator(let c):
            return c.startedAt ?? Date()
        case .creatorUpload(let u):
            return u.releasedAt ?? .distantPast
        }
    }
}

struct HomeHeroCarousel: View {
    let items: [HeroItem]
    let onSelectMedia: (TMDBResult, Platform?) -> Void
    let onSelectGame: (SportsGame) -> Void
    let onSelectLiveCreator: (HeroLiveCreator) -> Void
    let onSelectCreatorUpload: (NewEpisodeRow) -> Void

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
                        case .liveCreator(let creator):
                            onSelectLiveCreator(creator)
                        case .creatorUpload(let upload):
                            onSelectCreatorUpload(upload)
                        }
                    }
                    .containerRelativeFrame(.horizontal) { length, _ in
                        // Slightly narrower than the container so the next
                        // card peeks ~26pt past the right edge.
                        max(length - 60, 240)
                    }
                    .scrollTransition(.interactive) { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.92)
                            .scaleEffect(phase.isIdentity ? 1 : 0.985)
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
        case .liveCreator(let c): return brandColor(for: c).opacity(0.45)
        case .creatorUpload(let u): return uploadBrandColor(for: u).opacity(0.45)
        }
    }

    private var glowColor: Color {
        switch item {
        case .media: return Color.orange.opacity(0.18)
        case .game: return Color.blue.opacity(0.24)
        case .liveCreator(let c): return brandColor(for: c).opacity(0.30)
        case .creatorUpload(let u): return uploadBrandColor(for: u).opacity(0.30)
        }
    }

    private func brandColor(for creator: HeroLiveCreator) -> Color {
        Color(hex: creator.kind.brandColor) ?? Color.red
    }

    private func uploadBrandColor(for upload: NewEpisodeRow) -> Color {
        let kind = SourceKind.from(titleId: upload.titleId)
        return Color(hex: kind.brandColor) ?? Color.red
    }

    @ViewBuilder
    private var backdrop: some View {
        switch item {
        case .media(let result, _): mediaBackdrop(result)
        case .game(let game): sportsBackdrop(game)
        case .liveCreator(let creator): liveCreatorBackdrop(creator)
        case .creatorUpload(let upload): creatorUploadBackdrop(upload)
        }
    }

    private func liveCreatorBackdrop(_ creator: HeroLiveCreator) -> some View {
        let c = brandColor(for: creator)
        return Color.black
            .overlay {
                RemoteImage(
                    urlString: creator.avatarUrl,
                    contentMode: .fill,
                    fallbackColors: [c.opacity(0.85), c.opacity(0.30)]
                )
                .allowsHitTesting(false)
            }
    }

    private func creatorUploadBackdrop(_ upload: NewEpisodeRow) -> some View {
        let c = uploadBrandColor(for: upload)
        return Color.black
            .overlay {
                RemoteImage(
                    urlString: upload.thumbnailUrl ?? upload.posterUrl,
                    contentMode: .fill,
                    fallbackColors: [c.opacity(0.85), c.opacity(0.30)]
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
        case .liveCreator(let creator): liveCreatorContent(creator)
        case .creatorUpload(let upload): creatorUploadContent(upload)
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
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
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

    // MARK: - Creator live content

    private func liveCreatorContent(_ creator: HeroLiveCreator) -> some View {
        let c = brandColor(for: creator)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                livePill
                platformBadge(kind: creator.kind, color: c)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text(creator.streamTitle ?? creator.displayName)
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: Color.black.opacity(0.45), radius: 8, y: 2)

                liveCreatorMetaRow(creator)

                ctaPill(label: "Watch live", tint: c)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var livePill: some View {
        HStack(spacing: 5) {
            Circle().fill(.white).frame(width: 6, height: 6)
            Text("LIVE")
                .scaledFont(size: 10, weight: .black)
                .tracking(0.8)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255)))
    }

    private func liveCreatorMetaRow(_ creator: HeroLiveCreator) -> some View {
        HStack(spacing: 8) {
            Text(creator.displayName)
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 150)
            if let cat = creator.category, !cat.isEmpty {
                metaDot
                Text(cat)
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120)
            }
            if let viewers = creator.viewerCount, viewers > 0 {
                metaDot
                Text(compactViewerCount(viewers))
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
    }

    private func compactViewerCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM watching", Double(n) / 1_000_000.0) }
        if n >= 1_000 { return String(format: "%.1fK watching", Double(n) / 1_000.0) }
        return "\(n) watching"
    }

    // MARK: - Creator upload content

    private func creatorUploadContent(_ upload: NewEpisodeRow) -> some View {
        let c = uploadBrandColor(for: upload)
        let kind = SourceKind.from(titleId: upload.titleId)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                platformBadge(kind: kind, color: c)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text(upload.episodeTitle ?? upload.title ?? "")
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: Color.black.opacity(0.45), radius: 8, y: 2)

                creatorUploadMetaRow(upload)

                ctaPill(label: "Watch", tint: c)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func creatorUploadMetaRow(_ upload: NewEpisodeRow) -> some View {
        HStack(spacing: 8) {
            Text(upload.title ?? "")
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 150)
            if let date = upload.releasedAt {
                metaDot
                Text(Self.relativeDate(date))
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Platform badges (in-code vector, no asset dependency)

    private func platformBadge(kind: SourceKind, color: Color) -> some View {
        HStack(spacing: 4) {
            platformLogoMark(kind: kind, size: 10)
            Text(kind.displayLabel.uppercased())
                .scaledFont(size: 7, weight: .black)
                .tracking(0.6)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(color))
    }

    @ViewBuilder
    private func platformLogoMark(kind: SourceKind, size: CGFloat) -> some View {
        switch kind {
        case .youtube:
            // Red rounded rectangle with centered white play triangle — the
            // recognizable YouTube icon shape rendered in code so no asset
            // catalog entry is needed.
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255))
                    .frame(width: size * 1.45, height: size)
                Triangle()
                    .fill(.white)
                    .frame(width: size * 0.38, height: size * 0.42)
            }
        case .twitch:
            // Simplified Twitch glitch/speech-bubble mark — a rounded-top
            // rectangle with a notched bottom-left and two short vertical bars.
            TwitchMark()
                .fill(Color(red: 0x91/255, green: 0x46/255, blue: 0xFF/255))
                .frame(width: size, height: size)
        case .kick:
            // Bold "K" in a rounded square — Kick's distinctive glyph.
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0x53/255, green: 0xFC/255, blue: 0x18/255))
                    .frame(width: size, height: size)
                Text("K")
                    .scaledFont(size: size * 0.65, weight: .black)
                    .foregroundStyle(Color(red: 0.02, green: 0.02, blue: 0.04))
            }
        default:
            EmptyView()
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
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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

// MARK: - Platform logo shapes (in-code vectors, no asset dependency)

/// Simple right-pointing play triangle used in the in-code YouTube mark.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Simplified Twitch "glitch" / speech-bubble mark rendered as a SwiftUI
/// Shape so the brand logo never depends on an asset catalog image.
private struct TwitchMark: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        // Rounded-top square body
        p.move(to: CGPoint(x: w * 0.05, y: h * 0.15))
        p.addLine(to: CGPoint(x: w * 0.05, y: h * 0.90))
        p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.90))
        // Stepped bottom-left notch
        p.addLine(to: CGPoint(x: w * 0.25, y: h * 0.72))
        p.addLine(to: CGPoint(x: w * 0.08, y: h * 0.72))
        p.addLine(to: CGPoint(x: w * 0.08, y: h * 0.15))
        p.closeSubpath()
        // First short vertical bar
        p.move(to: CGPoint(x: w * 0.38, y: h * 0.22))
        p.addLine(to: CGPoint(x: w * 0.38, y: h * 0.52))
        p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.52))
        p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.22))
        p.closeSubpath()
        // Second short vertical bar
        p.move(to: CGPoint(x: w * 0.55, y: h * 0.22))
        p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.52))
        p.addLine(to: CGPoint(x: w * 0.65, y: h * 0.52))
        p.addLine(to: CGPoint(x: w * 0.65, y: h * 0.22))
        p.closeSubpath()
        return p
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
