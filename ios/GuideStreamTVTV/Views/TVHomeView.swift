//
//  TVHomeView.swift
//  GuideStreamTVTV
//
//  Living-room home: cinematic hero carousel on top, followed by rails
//  for Trending, New Episodes (on the air), News, and Sports. Every
//  focusable card defers to its own action so navigation can flow back
//  through a single sheet pattern instead of nested stacks.
//

import SwiftUI

struct TVHomeView: View {
    @State private var trending: [TVTMDBResult] = []
    @State private var newEpisodes: [TVTMDBResult] = []
    @State private var sports: [TVSportsGame] = []
    @State private var isLoading: Bool = true

    @State private var pendingDetail: TVTitleDetail?

    @State private var streams = TVStreamsViewModel.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 56) {
                heroSection
                    .padding(.top, 8)

                if !trending.isEmpty {
                    TVRail(title: "Trending Now", accent: TVTheme.orange, count: trending.count) {
                        ForEach(trending) { item in
                            posterCard(for: item, accent: TVTheme.orange)
                        }
                    }
                } else if isLoading {
                    loadingRail(title: "Trending Now", accent: TVTheme.orange)
                }

                if !newEpisodes.isEmpty {
                    TVRail(title: "New Episodes", accent: TVTheme.blue, count: newEpisodes.count) {
                        ForEach(newEpisodes) { item in
                            posterCard(for: item, accent: TVTheme.blue)
                        }
                    }
                }

                if !sports.isEmpty {
                    TVRail(title: "Live Sports", accent: TVTheme.blue, count: sports.count) {
                        ForEach(sports) { game in
                            TVSportsTile(game: game) { /* read-only for v1 */ }
                        }
                    }
                }

                Color.clear.frame(height: 40)
            }
        }
        .background(TVTheme.backgroundGradient)
        .task { await loadAll() }
        .sheet(item: $pendingDetail) { detail in
            TVTitleSheet(detail: detail) { isSaved in
                pendingDetail = nil
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroSection: some View {
        if trending.isEmpty {
            // Reserve the same height so the rails below don't jump
            // when the data lands.
            Rectangle()
                .fill(TVTheme.surface)
                .frame(height: 640)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(2)
                            .tint(.white)
                    }
                }
        } else {
            TVHeroCarousel(
                items: Array(trending.prefix(6)),
                onToggleSave: { item in
                    Task {
                        await streams.toggle(
                            titleId: item.canonicalTitleId,
                            title: item.displayName,
                            posterUrl: item.posterUrl,
                            platform: nil
                        )
                    }
                },
                isSaved: { item in streams.contains(titleId: item.canonicalTitleId) }
            )
        }
    }

    // MARK: - Cards

    private func posterCard(for item: TVTMDBResult, accent: Color) -> some View {
        TVPosterCard(
            title: item.displayName,
            subtitle: item.isTV ? "Series" : "Movie",
            posterUrl: item.posterUrl,
            accent: accent,
            isSaved: streams.contains(titleId: item.canonicalTitleId)
        ) {
            pendingDetail = TVTitleDetail(
                titleId: item.canonicalTitleId,
                title: item.displayName,
                overview: item.overview,
                posterUrl: item.posterUrl,
                backdropUrl: item.backdropUrl,
                tag: item.isTV ? "SERIES" : "MOVIE",
                accent: accent,
                year: item.year,
                platform: nil,
                isTVHint: item.isTV
            )
        }
    }

    // MARK: - Loading placeholders

    private func loadingRail(title: String, accent: Color) -> some View {
        TVRail(title: title, accent: accent, count: nil) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TVTheme.surface)
                    .frame(width: 260, height: 380)
                    .overlay {
                        TVShimmer()
                            .clipShape(.rect(cornerRadius: 18))
                    }
            }
        }
    }

    // MARK: - Data loading

    private func loadAll() async {
        isLoading = true
        async let trendingTask = (try? TVTMDBService.shared.getTrending()) ?? []
        async let newEpisodesTask = (try? TVTMDBService.shared.getOnTheAir()) ?? []
        async let sportsTask = TVSportsService.shared.fetchAll()
        async let watchTask: Void = TVStreamsViewModel.shared.fetchUserStreams()

        let (t, ne, sp, _) = await (trendingTask, newEpisodesTask, sportsTask, watchTask)
        self.trending = t
        self.newEpisodes = ne
        self.sports = sp
        self.isLoading = false
    }
}
