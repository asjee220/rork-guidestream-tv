//
//  MacComponents.swift
//  GuideStreamTVMac
//
//  Layout tokens approved in the Mac shell mockup (28 Sep 2026) and the
//  Home building blocks, styled after the phone's HomeView:
//  SectionGlassCard, poster badges, the hero carousel and Today's Pick.
//

import SwiftUI

enum MacLayout {
    static let sidebarWidth: CGFloat = 200
    static let railWidth: CGFloat = 76
    static let posterWidth: CGFloat = 150
    static let heroHeight: CGFloat = 250
    static let todaysPickBackdropHeight: CGFloat = 260
    static let cardRadius: CGFloat = 12
    static let contentPadding: CGFloat = 24
}

enum MacColor {
    static let navy = Color(red: 0x04 / 255, green: 0x09 / 255, blue: 0x0F / 255)
    static let surface = Color(red: 0x0B / 255, green: 0x12 / 255, blue: 0x1C / 255)
    static let elevated = Color(red: 0x12 / 255, green: 0x1B / 255, blue: 0x2A / 255)
    static let sheet = Color(red: 0x1B / 255, green: 0x27 / 255, blue: 0x39 / 255)
    static let orange = Color(red: 0xF5 / 255, green: 0x82 / 255, blue: 0x1F / 255)
    static let blue = Color(red: 0x1A / 255, green: 0x6F / 255, blue: 0xE8 / 255)
    static let gold = Color(red: 0xB8 / 255, green: 0x90 / 255, blue: 0x2A / 255)
    static let live = Color(red: 0xE5 / 255, green: 0x09 / 255, blue: 0x14 / 255)
    static let text2 = Color.white.opacity(0.62)
    static let text3 = Color.white.opacity(0.38)
    static let hairline = Color.white.opacity(0.10)
}

extension Color {
    /// "RRGGBB" / "#RRGGBB". Non-failable, like the tvOS target's, because
    /// UserAvatar's preset gradients rely on that signature.
    init(hex: String) {
        self = Color.fromHex(hex) ?? .gray
    }

    /// Optional form for data that may be missing (ESPN team colours).
    static func fromHex(_ hex: String?) -> Color? {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Screen background: navy with the blue haze top-centre and the warm glow
/// bottom-right, the same stack as TVTheme.backgroundGradient at desktop scale.
struct MacBackground: View {
    var body: some View {
        ZStack {
            MacColor.navy
            RadialGradient(colors: [Color(red: 0x08 / 255, green: 0x1A / 255, blue: 0x33 / 255).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.55, y: 0.2), startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Color(red: 0x4B / 255, green: 0x1C / 255, blue: 0x08 / 255).opacity(0.4), .clear],
                           center: UnitPoint(x: 0.9, y: 0.95), startRadius: 0, endRadius: 800)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Title reference

/// Everything the title sheet needs to open without a network call.
struct MacTitleRef: Identifiable, Hashable {
    let titleId: String
    let tmdbId: Int?
    let isTV: Bool
    let title: String
    var posterUrl: String?
    var backdropUrl: String?
    var overview: String?
    var year: Int?
    var id: String { titleId }

    init(result: TVTMDBResult) {
        titleId = result.canonicalTitleId
        tmdbId = result.id
        isTV = result.isTV
        title = result.displayName
        posterUrl = result.posterUrl
        backdropUrl = result.backdropUrl
        overview = result.overview
        year = result.year
    }

    init(titleId: String, tmdbId: Int?, isTV: Bool, title: String,
         posterUrl: String? = nil, backdropUrl: String? = nil, overview: String? = nil, year: Int? = nil) {
        self.titleId = titleId
        self.tmdbId = tmdbId
        self.isTV = isTV
        self.title = title
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.overview = overview
        self.year = year
    }
}

private struct OpenTitleKey: EnvironmentKey {
    static let defaultValue: (MacTitleRef) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Opens the title sheet. Set once by MacMainView.
    var openTitle: (MacTitleRef) -> Void {
        get { self[OpenTitleKey.self] }
        set { self[OpenTitleKey.self] = newValue }
    }
}

// MARK: - Section card (phone's SectionGlassCard)

struct MacSectionCard<Content: View>: View {
    let title: String
    var seeAllColor: Color? = nil
    var subtitle: String? = nil
    var highlighted: Bool = false
    var onSeeAll: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if let onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 3) {
                            Text("See all").font(.system(size: 13, weight: .semibold))
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(seeAllColor ?? MacColor.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, subtitle == nil ? 10 : 2)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(MacColor.text2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            content()
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacColor.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(highlighted ? MacColor.orange.opacity(0.55) : MacColor.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Horizontal rail inside a section card.
struct MacRail<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) { content() }
                .padding(.horizontal, 14)
        }
    }
}

// MARK: - Poster card

enum MacPosterBadge {
    case none
    case tag(String, Color)            // service or kind, bottom-left
    case match(Int, gold: Bool = false) // centred match pill
    case newToday(rating: Double?)     // rating top-right + NEW TODAY band
    case rating(Double?)
    case rank(Int)
    case leaving(String)
}

struct MacPosterCard: View {
    let title: String
    var subtitle: String? = nil
    let posterUrl: String?
    var badge: MacPosterBadge = .none
    var dateBand: String? = nil
    var width: CGFloat = MacLayout.posterWidth
    var aspect: CGFloat = 2.0 / 3.0
    var progress: Double? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    TVRemoteImage(urlString: posterUrl, contentMode: .fill)
                        .frame(width: width, height: width / aspect)
                        .clipped()
                    overlay
                }
                .frame(width: width, height: width / aspect)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 10, bottomLeadingRadius: dateBand == nil ? 10 : 0,
                    bottomTrailingRadius: dateBand == nil ? 10 : 0, topTrailingRadius: 10,
                    style: .continuous))
                .overlay(alignment: .bottom) {
                    if let dateBand {
                        Text(dateBand)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.1, green: 0.06, blue: 0.02))
                            .frame(width: width)
                            .padding(.vertical, 6)
                            .background(MacColor.orange)
                            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
                            .offset(y: 28)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: hovering ? 2 : 0)
                )
                .padding(.bottom, dateBand == nil ? 0 : 28)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(MacColor.text3)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var overlay: some View {
        switch badge {
        case .none:
            EmptyView()
        case .tag(let label, let color):
            VStack { Spacer(); HStack { pill(label, color); Spacer() } }.padding(8)
        case .match(let pct, let gold):
            VStack { Spacer(); pill("\(pct)% Match", gold ? MacColor.gold : MacColor.blue) }.padding(8)
        case .newToday(let rating):
            ZStack {
                ratingChip(rating)
                VStack {
                    Spacer()
                    Text("NEW TODAY")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(MacColor.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                        .background(LinearGradient(colors: [.clear, Color(red: 0.47, green: 0.2, blue: 0).opacity(0.85)],
                                                   startPoint: .top, endPoint: .bottom))
                }
            }
        case .rating(let rating):
            ratingChip(rating)
        case .rank(let n):
            VStack { HStack { Text("\(n)").font(.system(size: 30, weight: .heavy)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 6); Spacer() }; Spacer() }.padding(8)
        case .leaving(let date):
            VStack { Spacer(); HStack { pill("Leaves \(date)", Color(red: 0.7, green: 0.15, blue: 0.12)); Spacer() } }.padding(8)
        }
        if let progress {
            VStack {
                Spacer()
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(MacColor.orange).frame(width: g.size.width * progress)
                    }
                }
                .frame(height: 4)
                .padding(8)
            }
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color, in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder private func ratingChip(_ rating: Double?) -> some View {
        if let rating, rating > 0 {
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color(red: 1, green: 0.78, blue: 0.24))
                        Text(String(format: "%.1f", rating)).font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.55), in: Capsule())
                }
                Spacer()
            }
            .padding(8)
        }
    }
}

// MARK: - Hero carousel (phone's HomeHeroCarousel)

struct MacHeroCarousel: View {
    let entries: [MacHeroEntry]
    let onSelect: (MacHeroEntry) -> Void

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(max(geo.size.width - 60, 240), 460)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(entries) { entry in
                        MacHeroCard(entry: entry) { onSelect(entry) }
                            .frame(width: cardWidth, height: MacLayout.heroHeight)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .frame(height: MacLayout.heroHeight + 20)
        .padding(.vertical, -10)
    }
}

private struct MacHeroCard: View {
    let entry: MacHeroEntry
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                backdrop
                LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.45), .black.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                content.padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(hovering ? Color.white : tint.opacity(0.35), lineWidth: hovering ? 2 : 1))
            .shadow(color: tint.opacity(0.2), radius: 8, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var tint: Color {
        switch entry {
        case .media: return MacColor.orange
        case .game: return MacColor.blue
        case .liveCreator: return Color(red: 0x91 / 255, green: 0x46 / 255, blue: 1)
        case .upload: return .red
        }
    }

    @ViewBuilder private var backdrop: some View {
        switch entry {
        case .media(let r, _):
            TVRemoteImage(urlString: r.backdropUrl ?? r.posterUrl, contentMode: .fill)
        case .game(let g):
            ZStack {
                LinearGradient(colors: [Color.fromHex(g.away.primaryHex) ?? MacColor.blue, Color.fromHex(g.home.primaryHex) ?? MacColor.navy],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack {
                    Text(g.away.abbreviation).font(.system(size: 96, weight: .black)).offset(x: -8, y: -22)
                    Spacer()
                    Text(g.home.abbreviation).font(.system(size: 96, weight: .black)).offset(x: 8, y: 22)
                }
                .foregroundStyle(.white.opacity(0.10))
                .padding(.horizontal, 4)
            }
        case .liveCreator(_, _, _, _, let imageUrl, _):
            TVRemoteImage(urlString: imageUrl, contentMode: .fill)
        case .upload(let u):
            TVRemoteImage(urlString: u.thumbnailUrl ?? u.posterUrl, contentMode: .fill)
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) { pills }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                Text(headline)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
                meta
                ctaPill.padding(.top, 6)
            }
        }
    }

    @ViewBuilder private var pills: some View {
        switch entry {
        case .media(_, let provider):
            badge("TRENDING", MacColor.orange)
            if let provider, let p = Platform.from(providerName: provider) { badge(p.displayName, p.color) }
        case .game(let g):
            if g.state == .live { liveBadge }
            badge(g.leagueShort.uppercased(), Color.white.opacity(0.2))
        case .liveCreator:
            liveBadge
            badge("TWITCH", Color(red: 0x91 / 255, green: 0x46 / 255, blue: 1))
        case .upload:
            badge("▶ YOUTUBE", .red)
        }
    }

    private var headline: String {
        switch entry {
        case .media(let r, _): return r.displayName
        case .game(let g): return "\(g.away.shortName) vs \(g.home.shortName)"
        case .liveCreator(_, let name, let streamTitle, _, _, _): return streamTitle ?? name
        case .upload(let u): return u.episodeTitle ?? u.title ?? u.showName
        }
    }

    @ViewBuilder private var meta: some View {
        HStack(spacing: 8) {
            switch entry {
            case .media(let r, _):
                metaText(r.isTV ? "Series" : "Movie")
                if let y = r.year { dot; metaText(String(y)) }
                if let v = r.voteAverage, v > 0 {
                    dot
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Color(red: 1, green: 0.78, blue: 0.24))
                    Text(String(format: "%.1f", v)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                }
            case .game(let g):
                if g.state != .pre {
                    metaText(g.away.abbreviation)
                    Text(g.away.score).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    Text("–").foregroundStyle(Color.white.opacity(0.4))
                    Text(g.home.score).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    metaText(g.home.abbreviation)
                    dot
                }
                metaText(g.statusDetail)
            case .liveCreator(_, let name, _, let category, _, let viewers):
                metaText(name)
                if let category { dot; metaText(category) }
                if let viewers { dot; Text(Self.compact(viewers)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white) }
            case .upload(let u):
                metaText(u.showName)
                if let d = u.releasedAt { dot; metaText(Self.relative(d)) }
            }
        }
    }

    private var ctaPill: some View {
        let (label, color): (String, Color) = {
            switch entry {
            case .media: return ("Play", MacColor.orange)
            case .game(let g): return (g.broadcasts.first.map { "Watch on \($0)" } ?? "Watch", MacColor.blue)
            case .liveCreator: return ("Watch live", Color(red: 0.7, green: 0.55, blue: 1))
            case .upload: return ("Watch", Color(red: 1, green: 0.3, blue: 0.3))
            }
        }()
        return HStack(spacing: 8) {
            Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
            Text(label).font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(color, lineWidth: 1.5))
    }

    private func badge(_ text: String, _ bg: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(bg))
    }

    private var liveBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(.white).frame(width: 6, height: 6)
            Text("LIVE").font(.system(size: 10.5, weight: .heavy))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(MacColor.live))
    }

    private var dot: some View { Text("·").foregroundStyle(Color.white.opacity(0.4)) }
    private func metaText(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(0.75)).lineLimit(1)
    }

    static func compact(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000).replacingOccurrences(of: ".0K", with: "K") : "\(n)"
    }

    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Today's Pick (phone's TodaysPickSection)

struct MacTodaysPickCard: View {
    let pick: TVStreamingRelease
    let backdropUrl: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill").font(.system(size: 17, weight: .bold))
                    Text("TODAY'S PICK").font(.system(size: 15, weight: .heavy)).tracking(1.2)
                    Spacer()
                    Text(Self.dateString)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .foregroundStyle(MacColor.orange)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // A 16:9 backdrop cropped to a desktop-wide 260pt strip loses
                // most of the frame, so the whole frame sits centred at 16:9
                // over a blurred fill of itself. Sizes are explicit so the
                // fill image cannot grow the stack past the strip.
                GeometryReader { geo in
                    let h = MacLayout.todaysPickBackdropHeight
                    let art = backdropUrl ?? posterUrl
                    let artWidth = min(geo.size.width, h * 16 / 9)
                    ZStack {
                        TVRemoteImage(urlString: art, contentMode: .fill)
                            .frame(width: geo.size.width, height: h)
                            .clipped()
                            .blur(radius: 30)
                            .opacity(0.5)
                        TVRemoteImage(urlString: art, contentMode: backdropUrl == nil ? .fit : .fill)
                            .frame(width: artWidth, height: h)
                            .clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    }
                    .frame(width: geo.size.width, height: h)
                    .clipped()
                }
                .frame(height: MacLayout.todaysPickBackdropHeight)

                VStack(alignment: .leading, spacing: 10) {
                    Text(pick.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if pick.isOriginal == true, let src = pick.sourceName, !src.isEmpty {
                        Text("\(src) Original")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    if let src = pick.sourceName, !src.isEmpty {
                        let platform = Platform.from(providerName: src)
                        HStack(spacing: 6) {
                            Circle().fill(platform?.color ?? Color.white.opacity(0.25)).frame(width: 8, height: 8)
                            Text(platform?.displayName ?? src).font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(platform?.color ?? Color.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((platform?.color ?? Color.white.opacity(0.15)).opacity(0.15), in: Capsule())
                    }
                    Text(ctaText)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(red: 0.03, green: 0.02, blue: 0.02))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(MacColor.orange, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(16)
            }
            .background(MacColor.navy.opacity(0.95))
            .overlay(RoundedRectangle(cornerRadius: MacLayout.cardRadius).stroke(MacColor.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: MacLayout.cardRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var posterUrl: String? {
        pick.posterUrl?.isEmpty == false ? pick.posterUrl : TVTMDBImage.url(pick.posterPath, size: .poster500)
    }

    private var ctaText: String {
        guard let src = pick.sourceName, !src.isEmpty else { return "Watch now" }
        return AuthViewModel.shared.subscribesToService(named: src) ? "Watch on \(src)" : "Get on \(src)"
    }

    private static var dateString: String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.string(from: Date())
    }
}
