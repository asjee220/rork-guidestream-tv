//
//  MacHomeView.swift
//  GuideStreamTVMac
//
//  Home, in the phone's order (approved "iOS parity" layout): search bar,
//  hero carousel, Recommended for You, Today's Pick, New Episodes, Around
//  the World, Coming to Streaming, New This Week, Top Picks, Creators /
//  Podcasts, Everyone's Watching, Leaving Soon, Popular on <service>,
//  Continue Watching. Rails with nothing to show are omitted, as on iOS.
//

import SwiftUI

struct MacHomeView: View {
    let onSearch: () -> Void
    @State private var model = MacHomeModel.shared
    @State private var streams = TVStreamsViewModel.shared
    @State private var seeAll: MacSeeAllPayload?
    @Environment(\.openTitle) private var openTitle

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                searchBar

                if !model.heroEntries.isEmpty {
                    MacHeroCarousel(entries: model.heroEntries, onSelect: selectHero)
                } else if model.isLoading {
                    RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06))
                        .frame(height: MacLayout.heroHeight)
                }

                if !model.recommendedTitles.isEmpty {
                    MacSectionCard(title: "Recommended for You") {
                        MacRail {
                            ForEach(model.recommendedTitles) { r in
                                MacPosterCard(title: r.title, posterUrl: r.posterUrl, badge: .match(r.matchPercentage)) {
                                    openTitle(MacTitleRef(titleId: "tmdb:\(r.mediaType):\(r.tmdbId)", tmdbId: r.tmdbId,
                                                          isTV: r.isTV, title: r.title, posterUrl: r.posterUrl,
                                                          backdropUrl: r.backdropUrl))
                                }
                            }
                        }
                    }
                }

                if let pick = model.todaysPick {
                    MacTodaysPickCard(pick: pick, backdropUrl: model.todaysPickBackdropUrl) {
                        openTitle(MacTitleRef(titleId: "tmdb:\(pick.isTV ? "tv" : "movie"):\(pick.tmdbId)",
                                              tmdbId: pick.tmdbId, isTV: pick.isTV, title: pick.title,
                                              posterUrl: pick.posterUrl ?? TVTMDBImage.url(pick.posterPath, size: .poster500),
                                              backdropUrl: model.todaysPickBackdropUrl))
                    }
                }

                if !model.followedNewEpisodes.isEmpty {
                    MacSectionCard(title: "New Episodes") {
                        MacRail {
                            ForEach(model.followedNewEpisodes) { ep in
                                let p = Platform.from(providerName: ep.platform)
                                MacPosterCard(title: ep.showName, subtitle: episodeLabel(ep), posterUrl: ep.posterUrl,
                                              badge: p.map { .tag($0.name, $0.color) } ?? .none) {
                                    if let id = ep.tmdbId {
                                        openTitle(MacTitleRef(titleId: "tmdb:tv:\(id)", tmdbId: id, isTV: true,
                                                              title: ep.showName, posterUrl: ep.posterUrl))
                                    }
                                }
                            }
                        }
                    }
                }

                if !model.aroundTheWorld.isEmpty, let country = model.aroundCountry {
                    MacSectionCard(title: "Around the World",
                                   subtitle: "Streaming in \(country.displayName) today\(model.aroundProviderName.map { " · \($0)" } ?? "")") {
                        MacRail {
                            ForEach(Array(model.aroundTheWorld.enumerated()), id: \.element.id) { i, r in
                                MacPosterCard(title: r.displayName, subtitle: r.isTV ? "Series" : "Movie",
                                              posterUrl: r.posterUrl, badge: .rank(i + 1)) { openTitle(MacTitleRef(result: r)) }
                            }
                        }
                    }
                }

                if !model.comingToStreaming.isEmpty {
                    MacSectionCard(title: "Coming to Streaming") {
                        MacRail {
                            ForEach(model.comingToStreaming) { item in
                                MacPosterCard(title: item.result.displayName, subtitle: item.meta,
                                              posterUrl: item.result.posterUrl, dateBand: item.badge) {
                                    openTitle(MacTitleRef(result: item.result))
                                }
                            }
                        }
                    }
                }

                if !model.newThisWeek.isEmpty {
                    MacSectionCard(title: "New This Week", highlighted: true,
                                   onSeeAll: { seeAll = .releases("New This Week", model.newThisWeek) }) {
                        MacRail {
                            ForEach(model.newThisWeek) { r in
                                MacPosterCard(title: r.title, subtitle: r.sourceName,
                                              posterUrl: r.posterUrl ?? TVTMDBImage.url(r.posterPath, size: .poster500),
                                              badge: .newToday(rating: nil)) { openRelease(r) }
                            }
                        }
                    }
                }

                if !model.topPicks.isEmpty {
                    MacSectionCard(title: "Top Picks for You", seeAllColor: MacColor.blue,
                                   onSeeAll: { seeAll = .results("Top Picks for You", model.topPicks.map(\.result)) }) {
                        MacRail {
                            ForEach(model.topPicks) { p in
                                MacPosterCard(title: p.result.displayName, posterUrl: p.result.posterUrl,
                                              badge: .match(p.matchPercent)) { openTitle(MacTitleRef(result: p.result)) }
                            }
                        }
                    }
                }

                if !model.recommendedCreators.isEmpty {
                    MacSectionCard(title: "Creators/Podcasts for You") {
                        MacRail {
                            ForEach(model.recommendedCreators) { c in
                                MacPosterCard(title: c.displayName, subtitle: c.category, posterUrl: c.imageUrl,
                                              badge: .match(c.matchPercentage, gold: true), aspect: 1) {
                                    openCreator(titleId: c.titleId)
                                }
                            }
                        }
                    }
                }

                if !model.everyonesWatching.isEmpty {
                    MacSectionCard(title: "Everyone's Watching",
                                   onSeeAll: { seeAll = .results("Everyone's Watching", model.everyonesWatching.map(\.result)) }) {
                        MacRail {
                            ForEach(model.everyonesWatching) { item in
                                MacPosterCard(title: item.result.displayName, subtitle: item.providerName,
                                              posterUrl: item.result.posterUrl, badge: .rank(item.rank)) {
                                    openTitle(MacTitleRef(result: item.result))
                                }
                            }
                        }
                    }
                }

                if !model.leavingSoon.isEmpty {
                    MacSectionCard(title: "Leaving Soon") {
                        MacRail {
                            ForEach(model.leavingSoon) { row in
                                MacPosterCard(title: row.title, subtitle: row.serviceName, posterUrl: row.posterUrl,
                                              badge: row.leavingDate.map { .leaving(Self.shortDate($0)) } ?? .none) {
                                    openTitle(MacTitleRef(titleId: "tmdb:\(row.isTV ? "tv" : "movie"):\(row.tmdbId)",
                                                          tmdbId: row.tmdbId, isTV: row.isTV, title: row.title,
                                                          posterUrl: row.posterUrl))
                                }
                            }
                        }
                    }
                }

                ForEach(model.popularOnServiceOrder, id: \.id) { service in
                    if let items = model.popularOnService[service.id], !items.isEmpty {
                        MacSectionCard(title: "Popular on \(service.name)",
                                       onSeeAll: { seeAll = .results("Popular on \(service.name)", items) }) {
                            MacRail {
                                ForEach(items) { r in
                                    MacPosterCard(title: r.displayName, posterUrl: r.posterUrl,
                                                  badge: .tag(service.name.uppercased(), service.color)) {
                                        openTitle(MacTitleRef(result: r))
                                    }
                                }
                            }
                        }
                    }
                }

                if !model.continueWatching.isEmpty {
                    MacSectionCard(title: "Continue Watching") {
                        MacRail {
                            ForEach(model.continueWatching) { item in
                                MacPosterCard(title: item.row.titleName, subtitle: item.subtitle,
                                              posterUrl: item.posterUrl) {
                                    openTitle(MacTitleRef(titleId: item.titleId, tmdbId: item.row.tmdbId,
                                                          isTV: item.row.isTV, title: item.row.titleName,
                                                          posterUrl: item.posterUrl))
                                }
                            }
                        }
                    }
                }
            }
            .padding(MacLayout.contentPadding)
        }
        .task { await model.loadAll() }
        .refreshable { await model.loadAll(force: true) }
        .sheet(item: $seeAll) { payload in
            MacSeeAllGrid(payload: payload)
        }
    }

    private var searchBar: some View {
        Button(action: onSearch) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.4))
                Text("Search shows, creators, podcasts…").font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.3))
                Spacer()
                Text("⌘F").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MacColor.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectHero(_ entry: MacHeroEntry) {
        switch entry {
        case .media(let r, _):
            openTitle(MacTitleRef(result: r))
        case .game(let g):
            WatchIntentLogger.shared.log(eventType: .cardTapped,
                                         titleId: WatchIntentLogger.titleSlug("\(g.away.abbreviation)-\(g.home.abbreviation)-\(g.sport)"),
                                         platformId: (g.broadcasts.first ?? "").lowercased(),
                                         metadata: ["section": "hero_carousel", "kind": "sport"])
        case .liveCreator(let titleId, _, _, _, _, _):
            openCreator(titleId: titleId)
        case .upload(let u):
            openCreator(titleId: u.titleId)
        }
    }

    private func openRelease(_ r: TVStreamingRelease) {
        openTitle(MacTitleRef(titleId: "tmdb:\(r.isTV ? "tv" : "movie"):\(r.tmdbId)", tmdbId: r.tmdbId,
                              isTV: r.isTV, title: r.title,
                              posterUrl: r.posterUrl ?? TVTMDBImage.url(r.posterPath, size: .poster500)))
    }

    /// Creators open on their own platform in the browser for now.
    private func openCreator(titleId: String) {
        if let url = MacCreatorLinks.url(for: titleId) {
            WatchIntentLogger.shared.log(eventType: .deeplinkFired, titleId: titleId,
                                         platformId: TVCreatorKind.from(titleId: titleId)?.rawValue,
                                         metadata: ["section": "home"])
            MacLinkOpener.open(url)
        }
    }

    private func episodeLabel(_ ep: TVNewEpisodeRow) -> String? {
        guard let s = ep.seasonValue, let e = ep.episodeValue else { return ep.episodeTitle }
        return "S\(s) · E\(e)"
    }

    static func shortDate(_ raw: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: String(raw.prefix(10))) else { return raw }
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

/// Web links for creator title ids ("yt:", "tw:", "kick:").
enum MacCreatorLinks {
    static func url(for titleId: String) -> URL? {
        let parts = titleId.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "yt": return URL(string: "https://www.youtube.com/channel/\(parts[1])")
        case "tw": return URL(string: "https://www.twitch.tv/\(parts[1])")
        case "kick": return URL(string: "https://kick.com/\(parts[1])")
        default: return nil
        }
    }
}

// MARK: - See all

enum MacSeeAllPayload: Identifiable {
    case results(String, [TVTMDBResult])
    case releases(String, [TVStreamingRelease])

    var id: String {
        switch self {
        case .results(let t, _), .releases(let t, _): return t
        }
    }
}

struct MacSeeAllGrid: View {
    let payload: MacSeeAllPayload
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openTitle) private var openTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 20, weight: .bold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: MacLayout.posterWidth), spacing: 14)], spacing: 18) {
                    ForEach(refs) { ref in
                        MacPosterCard(title: ref.title, posterUrl: ref.posterUrl) {
                            dismiss()
                            openTitle(ref)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(MacColor.navy)
    }

    private var title: String {
        switch payload {
        case .results(let t, _), .releases(let t, _): return t
        }
    }

    private var refs: [MacTitleRef] {
        switch payload {
        case .results(_, let items): return items.map { MacTitleRef(result: $0) }
        case .releases(_, let items):
            return items.map {
                MacTitleRef(titleId: "tmdb:\($0.isTV ? "tv" : "movie"):\($0.tmdbId)", tmdbId: $0.tmdbId, isTV: $0.isTV,
                            title: $0.title, posterUrl: $0.posterUrl ?? TVTMDBImage.url($0.posterPath, size: .poster500))
            }
        }
    }
}
