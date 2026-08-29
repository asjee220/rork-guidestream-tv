//
//  TVSearchView.swift
//  GuideStreamTVTV
//
//  Search and browse. Text entry is SwiftUI's own `.searchable`, which on
//  tvOS brings the system grid keyboard, Siri Remote dictation and recent
//  queries — none of which is worth rebuilding for a field people type six
//  characters into.
//
//  With no query the screen is a browse landing: the ten genres from
//  Shared/BrowseFilters.swift over a trending grid. Selecting a genre opens
//  TVBrowseResultsView; typing replaces the landing with results.
//

import SwiftUI

struct TVSearchView: View {
    @State private var query: String = ""
    @State private var results: [TVTMDBResult] = []
    @State private var trending: [TVTMDBResult] = []
    @State private var isSearching: Bool = false
    @State private var hasSearched: Bool = false

    @State private var pendingDetail: TVTitleDetail?
    @State private var browseGenre: BrowseGenre?

    @State private var streams = TVStreamsViewModel.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 26), count: 5)

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmedQuery.isEmpty {
                        browseLanding
                    } else {
                        searchResults
                    }
                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, 80)
            }
            .background(TVTheme.backgroundGradient)
            .searchable(
                text: $query,
                placement: .automatic,
                prompt: "Search shows, movies, creators"
            )
        }
        .task { await loadTrending() }
        .task(id: trimmedQuery) { await runSearch() }
        .sheet(item: $pendingDetail) { detail in
            TVTitleSheet(detail: detail) { _ in pendingDetail = nil }
        }
        .fullScreenCover(item: $browseGenre) { genre in
            TVBrowseResultsView(genre: genre, pendingDetail: $pendingDetail)
        }
    }

    // MARK: - Browse landing

    private var browseLanding: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Browse by genre")

            TVGenreTileGrid { genre in
                browseGenre = genre
            }

            if !trending.isEmpty {
                sectionTitle("Popular now")
                    .padding(.top, 52)

                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(trending.prefix(10)) { item in
                        posterCard(for: item)
                    }
                }
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isSearching {
                sectionTitle("Searching…")
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(TVTheme.surface)
                            .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    }
                }
            } else if results.isEmpty && hasSearched {
                sectionTitle("No results for “\(trimmedQuery)”")
                Text("Check the spelling, or browse by genre instead.")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(TVTheme.textSecondary)
                    .padding(.bottom, 40)

                TVGenreTileGrid { genre in
                    browseGenre = genre
                }
            } else {
                sectionTitle("\(results.count) result\(results.count == 1 ? "" : "s")")
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(results) { item in
                        posterCard(for: item)
                    }
                }
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: String) -> some View {
        HStack(spacing: 14) {
            Capsule()
                .fill(TVTheme.orange)
                .frame(width: 6, height: 30)
            Text(text)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(TVTheme.textPrimary)
        }
        .padding(.bottom, 24)
    }

    private func posterCard(for item: TVTMDBResult) -> some View {
        TVPosterCard(
            title: item.displayName,
            subtitle: item.isTV ? "Series" : "Movie",
            posterUrl: item.posterUrl,
            accent: TVTheme.orange,
            isSaved: streams.contains(titleId: item.canonicalTitleId)
        ) {
            pendingDetail = TVTitleDetail(
                titleId: item.canonicalTitleId,
                title: item.displayName,
                overview: item.overview,
                posterUrl: item.posterUrl,
                backdropUrl: item.backdropUrl,
                tag: item.isTV ? "SERIES" : "MOVIE",
                accent: TVTheme.orange,
                year: item.year,
                platform: nil,
                isTVHint: item.isTV
            )
        }
    }

    // MARK: - Loading

    private func loadTrending() async {
        guard trending.isEmpty else { return }
        trending = (try? await TVTMDBService.shared.getTrending()) ?? []
    }

    /// Debounced so a grid keyboard does not fire a request per keypress.
    private func runSearch() async {
        let q = trimmedQuery
        guard !q.isEmpty else {
            results = []
            hasSearched = false
            isSearching = false
            return
        }

        isSearching = true
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        let found = (try? await TVTMDBService.shared.searchContent(query: q)) ?? []
        guard !Task.isCancelled else { return }

        results = found
        hasSearched = true
        isSearching = false

        WatchIntentLogger.shared.log(
            eventType: .searchQuery,
            metadata: ["query": q, "result_count": found.count, "surface": "tv_search"]
        )
    }
}
