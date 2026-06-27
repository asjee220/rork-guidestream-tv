//
//  MoreEpisodesScreen.swift
//  GuideStreamTV
//
//  Full-screen episode browser organised by season, reachable from the
//  "More episodes" button in the ShowDetailScreen bottom action bar.
//

import SwiftUI

// MARK: - MoreEpisodesScreen

struct MoreEpisodesScreen: View {
    var titleId: String
    var title: String
    var posterUrl: String? = nil
    var isTV: Bool = true
    var onBack: () -> Void = {}

    @State private var vm = ShowDetailViewModel()
    @State private var activeSeason: Int = 1
    @State private var filter: EpisodeFilter = .unwatched

    enum EpisodeFilter: String, CaseIterable {
        case unwatched = "Unwatched"
        case watched = "Watched"
        case newEpisodes = "New"
    }

    private var totalEpisodeCount: Int {
        guard let tmdb = vm.tmdb, let count = tmdb.numberOfSeasons else { return 0 }
        // Approximate: each season has the same number of episodes as the
        // currently loaded season, rounded up by 10%. Not perfect, but
        // better than "0 episodes" before every season is loaded.
        let currentCount = vm.season?.episodes.count ?? 8
        return currentCount * count
    }

    private var episodes: [TMDBEpisode] { vm.season?.episodes ?? [] }

    private var nextEpisodeNumber: Int {
        episodes.last?.episodeNumber ?? episodes.first?.episodeNumber ?? 1
    }

    var body: some View {
        ZStack(alignment: .top) {
            BrandBackground()

            VStack(spacing: 0) {
                // ── Top bar ──────────────────────────────────────
                ZStack {
                    Color.navy.opacity(0.85)
                        .background(.ultraThinMaterial)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 1)
                        }

                    HStack(spacing: 12) {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .scaledFont(size: 14, weight: .semibold)
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)

                        Text("Episodes")
                            .scaledFont(size: 17, weight: .semibold)
                            .foregroundStyle(.white)

                        Spacer(minLength: 0)
                        Color.clear.frame(width: 32, height: 32)
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 56)

                // ── Content ──────────────────────────────────────
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {

                        // Show identity strip
                        showIdentityStrip

                        // Season picker
                        seasonPicker

                        // Season progress bar
                        seasonProgressBar

                        // Filter chips
                        filterChipsRow

                        // Episode list
                        episodeList
                    }
                    .padding(.bottom, 160)
                }

                // ── Sticky bottom bar ────────────────────────────
                stickyBottomBar
            }
        }
        .preferredColorScheme(.dark)
        .task(id: titleId) {
            await vm.loadIfNeeded(titleId: titleId, isTV: isTV)
            activeSeason = vm.tmdb?.numberOfSeasons ?? 1
            await vm.loadSeason(activeSeason)
        }
    }

    // MARK: - Show identity strip

    private var showIdentityStrip: some View {
        HStack(spacing: 12) {
            // Poster thumbnail
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 44, height: 66)
                .overlay {
                    RemoteImage(urlString: posterUrl)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(size: 16, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(vm.tmdb?.numberOfSeasons ?? 1) seasons · \(totalEpisodeCount) episodes")
                    .scaledFont(size: 11)
                    .foregroundStyle(Color.textSecondary)

                // Platform badge
                if let svc = vm.primaryService {
                    Text(shortName(svc.name))
                        .scaledFont(size: 9, weight: .heavy)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(svc.color)
                        )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Season picker

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let maxSeason = vm.tmdb?.numberOfSeasons ?? 1
                ForEach(Array(1...max(1, maxSeason)), id: \.self) { s in
                    Button("Season \(s)") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        activeSeason = s
                        Task { await vm.loadSeason(s) }
                    }
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(activeSeason == s ? .white : Color.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(activeSeason == s ? Color.orange : Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule().stroke(
                            activeSeason == s ? Color.orange : Color.white.opacity(0.15),
                            lineWidth: 1
                        )
                    )
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 14)
    }

    // MARK: - Season progress bar

    private var seasonProgressBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Season \(activeSeason) progress")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("0 of \(episodes.count)")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(Color.orange)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.orange)
                        .frame(width: 0, height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Filter chips

    private var filterChipsRow: some View {
        HStack(spacing: 8) {
            ForEach(EpisodeFilter.allCases, id: \.self) { f in
                let isActive = filter == f
                Button(f.rawValue) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        filter = f
                    }
                }
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(isActive ? Color.orange : Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isActive ? Color.orange.opacity(0.15) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(
                        isActive ? Color.orange : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
                )
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Episode list

    private var episodeList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, ep in
                Button {
                    WatchIntentLogger.shared.log(
                        eventType: .cardTapped,
                        titleId: titleId,
                        metadata: [
                            "season": activeSeason,
                            "episode": ep.episodeNumber,
                            "episode_name": ep.name ?? ""
                        ]
                    )
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        // Episode number
                        Text("\(ep.episodeNumber)")
                            .scaledFont(size: 12, weight: .bold)
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 24, alignment: .center)

                        // Thumbnail
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0x2D/255, green: 0x14/255, blue: 0x54/255),
                                        Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 88, height: 56)
                            .overlay {
                                RemoteImage(url: ep.stillUrl.flatMap { URL(string: $0) })
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .overlay {
                                Image(systemName: "play.circle.fill")
                                    .scaledFont(size: 22, weight: .regular)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .shadow(color: .black.opacity(0.4), radius: 4)
                            }

                        // Info
                        VStack(alignment: .leading, spacing: 3) {
                            Text("S:\(activeSeason) EP:\(ep.episodeNumber)")
                                .scaledFont(size: 9, weight: .semibold)
                                .foregroundStyle(Color.textTertiary)

                            Text(ep.name ?? "Episode \(ep.episodeNumber)")
                                .scaledFont(size: 13, weight: .bold)
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            if let overview = ep.overview, !overview.isEmpty {
                                Text(overview)
                                    .scaledFont(size: 11)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(2)
                            }

                            if let runtime = ep.runtime, runtime > 0 {
                                Text("\(runtime) min")
                                    .scaledFont(size: 10)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .scaledFont(size: 11, weight: .semibold)
                            .foregroundStyle(Color.white.opacity(0.15))
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Separator
                if idx < episodes.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.09))
                        .frame(height: 0.5)
                        .padding(.leading, 120)
                }
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - Sticky bottom bar

    private var stickyBottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            VStack(spacing: 6) {
                // Primary Play Next button
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if let svc = vm.primaryService {
                        if let url = vm.primaryDeeplink {
                            let finalURL = episodeDeeplinkURL(from: url, season: activeSeason, episode: nextEpisodeNumber)
                            StreamingDeepLinker.openResolvedURL(
                                finalURL, platform: svc.name, title: title,
                                tmdbId: Int(titleId)
                            )
                        } else {
                            StreamingDeepLinker.open(
                                platform: svc.name, title: title,
                                tmdbId: Int(titleId), isTV: isTV
                            )
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .scaledFont(size: 14, weight: .bold)
                        Text("Watch S:\(activeSeason) EP:\(nextEpisodeNumber)")
                            .scaledFont(size: 14, weight: .bold)
                            .lineLimit(1)
                        if let svc = vm.primaryService {
                            Text(shortName(svc.name))
                                .scaledFont(size: 9, weight: .heavy)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(svc.color)
                                )
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(Color.orange))
                    .shadow(color: Color.orange.opacity(0.35), radius: 14, y: 6)
                }
                .buttonStyle(.plain)

                // Ghost text buttons
                HStack(spacing: 8) {
                    Button(action: {}) {
                        HStack(spacing: 4) {
                            Image(systemName: "bell")
                                .scaledFont(size: 10, weight: .semibold)
                            Text("Alert for new episodes")
                                .scaledFont(size: 10, weight: .semibold)
                        }
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            Capsule().fill(Color.white.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {}) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .scaledFont(size: 10, weight: .semibold)
                            Text("Download season")
                                .scaledFont(size: 10, weight: .semibold)
                        }
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            Capsule().fill(Color.white.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(
                Color.navy.opacity(0.90)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    // MARK: - Helpers

    /// Builds an episode-specific deeplink URL by appending season/episode path
    /// segments to the show-level web_url.
    private func episodeDeeplinkURL(from base: URL, season: Int, episode: Int) -> URL {
        let baseStr = base.absoluteString
        let episodePath = "/season/\(season)/episode/\(episode)"
        if baseStr.contains("paramountplus.com") || baseStr.contains("paramount") {
            let stripped = baseStr.hasSuffix("/") ? String(baseStr.dropLast()) : baseStr
            return URL(string: stripped + episodePath) ?? base
        }
        if baseStr.contains("peacocktv.com") || baseStr.contains("peacock") {
            let stripped = baseStr.hasSuffix("/") ? String(baseStr.dropLast()) : baseStr
            return URL(string: stripped + episodePath) ?? base
        }
        if baseStr.contains("hulu.com") {
            let stripped = baseStr.hasSuffix("/") ? String(baseStr.dropLast()) : baseStr
            return URL(string: stripped + episodePath) ?? base
        }
        if baseStr.contains("amazon.com") || baseStr.contains("primevideo.com") || baseStr.contains("amazon") {
            return URL(string: baseStr + "?season=\(season)&episode=\(episode)") ?? base
        }
        return base
    }

    private func shortName(_ name: String) -> String {
        let key = name.lowercased()
        if key.contains("paramount") { return "P+" }
        if key.contains("disney") { return "D+" }
        if key.contains("apple") { return "TV+" }
        if key.contains("prime") || key.contains("amazon") { return "PRIME" }
        if key.contains("peacock") { return "PEACOCK" }
        if key.contains("netflix") { return "NETFLIX" }
        if key.contains("hulu") { return "HULU" }
        if key.contains("max") || key.contains("hbo") { return "MAX" }
        if key.contains("crunchyroll") { return "CR" }
        return String(name.prefix(4).uppercased())
    }
}

#Preview {
    MoreEpisodesScreen(titleId: "tt-succession", title: "Succession")
}
