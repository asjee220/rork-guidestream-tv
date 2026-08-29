//
//  TVBrowseResultsView.swift
//  GuideStreamTVTV
//
//  Filter-driven results grid behind a genre tile. Mirrors the phone app's
//  BrowseResultsView: genre chip rail, dismissible applied-filter pills, a
//  live result count, paging, an ad chip between grid chunks, and the
//  empty-state probe that relaxes one filter and offers it in words.
//
//  The query itself is TVTMDBService.discoverBrowse — the same call, with
//  the same parameters, that iPhone and Android have been running since
//  26 August.
//

import SwiftUI

struct TVBrowseResultsView: View {
    let genre: BrowseGenre
    @Binding var pendingDetail: TVTitleDetail?

    @State private var filters: BrowseFilters
    @State private var results: [TVTMDBResult] = []
    @State private var page: Int = 1
    @State private var totalPages: Int = 1
    @State private var totalResults: Int = 0
    @State private var isLoading: Bool = true
    @State private var isPaging: Bool = false
    @State private var recovery: TVBrowseRecovery?
    @State private var panelOpen: Bool = false
    @State private var chipSponsor: SponsoredChipData?

    @State private var streams = TVStreamsViewModel.shared

    @FocusState private var filtersButtonFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 26), count: 5)
    /// Two full rows between ad chips.
    private let adInterval = 10

    init(genre: BrowseGenre, pendingDetail: Binding<TVTitleDetail?>) {
        self.genre = genre
        self._pendingDetail = pendingDetail
        self._filters = State(initialValue: BrowseFilters(
            genreIds: [genre.id],
            providerIds: TVBrowseProviders.subscribedProviderIds()
        ))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    chipRail
                    countRow

                    if isLoading {
                        loadingGrid
                    } else if results.isEmpty {
                        emptyState
                    } else {
                        resultChunks
                    }

                    Color.clear.frame(height: 60)
                }
                .padding(.leading, 152)
                .padding(.trailing, panelOpen ? 640 : 80)
            }

            if panelOpen {
                TVBrowseFilterPanel(filters: $filters) {
                    panelOpen = false
                    filtersButtonFocused = true
                }
                .transition(.move(edge: .trailing))
            }
        }
        .background(TVTheme.backgroundGradient)
        .animation(.easeOut(duration: 0.25), value: panelOpen)
        .task(id: filters.signature) { await reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Capsule()
                .fill(TVTheme.orange)
                .frame(width: 6, height: 34)
            Text(genre.name)
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(TVTheme.textPrimary)

            Spacer()

            Button {
                panelOpen = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 18, weight: .bold))
                    Text(filters.activeCount == 0 ? "Filters" : "Filters (\(filters.activeCount))")
                        .font(.system(size: 20, weight: .semibold))
                }
                .foregroundStyle(filtersButtonFocused ? TVTheme.textPrimary : TVTheme.textSecondary)
                .padding(.horizontal, 26)
                .padding(.vertical, 11)
                .overlay {
                    Capsule().stroke(
                        filtersButtonFocused ? TVTheme.orange : Color.white.opacity(0.25),
                        lineWidth: filtersButtonFocused ? 2 : 1
                    )
                }
            }
            .buttonStyle(TVPanelButtonStyle())
            .focused($filtersButtonFocused)
            .focusEffectDisabled()
        }
        .padding(.top, 64)
    }

    // MARK: - Chip rail

    private var chipRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(BrowseCatalog.genres) { option in
                    TVGenreChip(
                        title: option.name,
                        isSelected: filters.genreIds == [option.id]
                    ) {
                        filters.genreIds = [option.id]
                    }
                }
            }
            .padding(.vertical, 26)
        }
    }

    // MARK: - Count row

    private var countRow: some View {
        HStack(spacing: 14) {
            ForEach(filters.pills) { pill in
                TVFilterPill(pill: pill) {
                    filters = filters.removing(pill.kind)
                }
            }

            Spacer()

            if !isLoading {
                Text("\(totalResults) titles · sorted by \(filters.sort.label)")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(TVTheme.textSecondary)
            }
        }
        .padding(.bottom, 22)
    }

    // MARK: - Grid

    /// Ads sit between chunked grids rather than inside one — a LazyVGrid
    /// has no cell spanning, same constraint the phone hit.
    private var resultChunks: some View {
        let chunks = stride(from: 0, to: results.count, by: adInterval).map { start in
            Array(results[start..<min(start + adInterval, results.count)])
        }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { chunkIndex, chunk in
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(chunk) { item in
                        posterCard(for: item)
                            .onAppear { pageInIfNeeded(at: item) }
                    }
                }

                if chunkIndex == 0, let chipSponsor {
                    TVSponsoredChip(data: chipSponsor)
                        .id("chip_\(chipSponsor.advertiser.key)_browse_\(genre.id)")
                        .padding(.vertical, 26)
                }
            }

            if isPaging {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: columns, spacing: 26) {
            ForEach(0..<10, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TVTheme.surface)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
            }
        }
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

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No titles match all your filters.")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(TVTheme.textPrimary)

            if let recovery {
                Text("Dropping \(recovery.label) brings back \(recovery.count) titles.")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(TVTheme.textSecondary)

                Button {
                    filters = filters.removing(recovery.kind)
                } label: {
                    Text("Drop \(recovery.label)")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 11)
                        .background(TVTheme.orange, in: Capsule())
                }
                .buttonStyle(TVPanelButtonStyle())
                .focusEffectDisabled()
                .padding(.top, 8)
            } else {
                Text("Try widening one of them.")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(TVTheme.textSecondary)
            }
        }
        .padding(34)
        .frame(maxWidth: 900, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
        }
    }

    // MARK: - Loading

    private func reload() async {
        isLoading = true
        recovery = nil
        chipSponsor = nil
        page = 1

        let snapshot = filters
        guard let result = try? await TVTMDBService.shared.discoverBrowse(snapshot, page: 1) else {
            results = []
            totalResults = 0
            isLoading = false
            return
        }

        results = result.results
        totalPages = result.totalPages
        totalResults = result.totalResults
        isLoading = false

        if result.results.isEmpty {
            recovery = await TVBrowseRecovery.probe(from: snapshot)
        } else {
            await TVAffiliateService.shared.fetchIfNeeded()
            chipSponsor = await resolveSponsor(from: result.results)
        }
    }

    private func pageInIfNeeded(at item: TVTMDBResult) {
        guard !isPaging, page < totalPages else { return }
        guard let index = results.firstIndex(where: { $0.id == item.id }) else { return }
        // Five cells a row burns a page in four rows, so ask early.
        guard index >= results.count - 10 else { return }

        isPaging = true
        let next = page + 1
        let snapshot = filters
        Task { @MainActor in
            defer { isPaging = false }
            guard let result = try? await TVTMDBService.shared.discoverBrowse(snapshot, page: next),
                  snapshot.signature == filters.signature else { return }
            var seen = Set(results.map(\.id))
            results.append(contentsOf: result.results.filter { seen.insert($0.id).inserted })
            page = result.page
            totalPages = result.totalPages
        }
    }

    /// First gap-service advertiser among the top of the grid, resolved the
    /// same way Home resolves its two chips.
    private func resolveSponsor(from items: [TVTMDBResult]) async -> SponsoredChipData? {
        for item in items.prefix(8) {
            let provider = try? await TVTMDBService.shared.getTopWatchProvider(
                tmdbId: item.id,
                isTV: item.isTV
            )
            guard let providerName = provider?.providerName else { continue }
            guard let advertiser = TVAffiliateService.shared.advertiser(forProviderName: providerName),
                  advertiser.appStoreURL != nil,
                  TVAffiliateService.shared.isGapService(providerName) else { continue }
            return SponsoredChipData(
                advertiser: advertiser,
                titleName: item.displayName,
                titleId: item.canonicalTitleId,
                providerName: providerName,
                surface: "browse_results"
            )
        }
        return nil
    }
}

// MARK: - Recovery probe

/// Re-runs the query with one filter relaxed, in priority order, and reports
/// the first that recovers titles. Bounded to three probes and only ever
/// reached on an empty grid — identical policy to the phone app.
struct TVBrowseRecovery: Sendable {
    let kind: BrowseFilterPill.Kind
    let label: String
    let count: Int

    static func probe(from filters: BrowseFilters) async -> TVBrowseRecovery? {
        let order: [(BrowseFilterPill.Kind, String)] = [
            (.rating, "the rating filter"),
            (.year, "the year filter"),
            (.mediaType, "the type filter"),
            (.services, "the services filter")
        ]

        var probes = 0
        for (kind, label) in order {
            guard probes < 3 else { return nil }
            let relaxed = filters.removing(kind)
            guard relaxed.signature != filters.signature else { continue }
            probes += 1
            guard let page = try? await TVTMDBService.shared.discoverBrowse(relaxed, page: 1),
                  !page.results.isEmpty else { continue }
            return TVBrowseRecovery(kind: kind, label: label, count: page.totalResults)
        }
        return nil
    }
}

// MARK: - Provider mapping

enum TVBrowseProviders {
    /// StreamingCatalog id -> TMDB watch-provider id. Same map the Home
    /// rails use to build "Popular on {service}".
    static let tmdbProviderIdMap: [String: Int] = [
        "netflix": 8, "prime": 9, "disney": 337, "max": 1899, "hulu": 15,
        "appletv": 350, "paramount": 2303, "peacock": 386, "starz": 43,
        "showtime": 37, "crunchyroll": 283, "youtube": 192
    ]

    static func subscribedProviderIds() -> [Int] {
        AuthViewModel.shared.selectedServices.compactMap { tmdbProviderIdMap[$0] }
    }
}

// MARK: - Chip + pill

private struct TVGenreChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(isSelected ? .white : (isFocused ? TVTheme.textPrimary : TVTheme.textSecondary))
                .padding(.horizontal, 26)
                .padding(.vertical, 11)
                .background(isSelected ? TVTheme.orange : Color.white.opacity(0.05), in: Capsule())
                .overlay {
                    Capsule().stroke(isFocused && !isSelected ? TVTheme.orange : Color.clear, lineWidth: 2)
                }
        }
        .buttonStyle(TVPanelButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

private struct TVFilterPill: View {
    let pill: BrowseFilterPill
    let onClear: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onClear) {
            HStack(spacing: 10) {
                Text(pill.label)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(TVTheme.textPrimary)
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TVTheme.textSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                (pill.accented ? TVTheme.orange.opacity(0.18) : Color.white.opacity(0.07)),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(
                    isFocused ? TVTheme.orange : Color.white.opacity(0.14),
                    lineWidth: isFocused ? 2 : 1
                )
            }
        }
        .buttonStyle(TVPanelButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .accessibilityLabel("Clear \(pill.label)")
    }
}
