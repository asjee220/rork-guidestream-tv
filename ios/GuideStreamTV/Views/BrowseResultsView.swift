//
//  BrowseResultsView.swift
//  GuideStreamTV
//
//  Filter-driven results grid behind a genre tile.
//
//  This is PopularOnServiceCategoriesView generalised: the same pill row over a
//  two-column poster grid with per-selection caching, freed from its single
//  provider and given an applied-filter bar, a result count, sort and paging.
//

import SwiftUI

// MARK: - Route

enum BrowseRoute: Hashable {
    case genre(String)
}

// MARK: - Recovery

/// The one filter whose removal brings the most titles back, offered on an
/// otherwise empty grid.
struct BrowseRecovery: Hashable, Sendable {
    let kind: BrowseFilterPill.Kind
    let label: String
    let count: Int
}

// MARK: - Model

@MainActor
@Observable
final class BrowseResultsModel {
    var filters: BrowseFilters

    private(set) var results: [TMDBResult] = []
    private(set) var totalResults: Int = 0
    private(set) var isLoading = false
    private(set) var isPaging = false
    private(set) var recovery: BrowseRecovery?

    private var page = 1
    private var totalPages = 1
    /// First page per filter signature, so flipping back to a genre you already
    /// looked at is instant — the same trick the service browser uses.
    private var cache: [String: BrowsePage] = [:]
    private var loadTask: Task<Void, Never>?

    init(genreId: String, providerIds: [Int]) {
        self.filters = BrowseFilters(genreIds: [genreId], providerIds: providerIds)
    }

    /// Providers are read from the auth store on appear rather than in the
    /// view's init, which is not main-actor isolated.
    func attachProviders(_ ids: [Int]) {
        guard filters.providerIds != ids else { return }
        filters.providerIds = ids
    }

    var genre: BrowseGenre? { filters.selectedGenres.first }
    var title: String { genre?.name ?? "Browse" }
    var canPage: Bool { page < totalPages && page < 500 }

    // MARK: Loading

    func reload() {
        loadTask?.cancel()
        let signature = filters.signature
        recovery = nil

        if let cached = cache[signature] {
            apply(cached, replacing: true)
            return
        }

        isLoading = true
        loadTask = Task {
            let page = try? await TMDBService.shared.discoverBrowse(filters, page: 1)
            guard !Task.isCancelled else { return }
            let resolved = page ?? .empty
            cache[signature] = resolved
            apply(resolved, replacing: true)
            isLoading = false
            if resolved.results.isEmpty { await probeRecovery() }
        }
    }

    func loadNextPage() {
        guard canPage, !isPaging, !isLoading else { return }
        isPaging = true
        let next = page + 1
        Task {
            defer { isPaging = false }
            guard let more = try? await TMDBService.shared.discoverBrowse(filters, page: next),
                  !Task.isCancelled else { return }
            apply(more, replacing: false)
        }
    }

    private func apply(_ browsePage: BrowsePage, replacing: Bool) {
        if replacing {
            results = browsePage.results
        } else {
            // TMDB pages overlap occasionally; never render the same id twice.
            let known = Set(results.map(\.id))
            results.append(contentsOf: browsePage.results.filter { !known.contains($0.id) })
        }
        page = browsePage.page
        totalPages = browsePage.totalPages
        totalResults = browsePage.totalResults
    }

    /// Walks the active filters from most to least restrictive and stops at the
    /// first one whose removal recovers titles. Bounded to three calls, and it
    /// only ever runs on an empty grid.
    private func probeRecovery() async {
        let priority: [BrowseFilterPill.Kind] = [.rating, .year, .mediaType, .services]
        let active = priority.filter { kind in filters.pills.contains { $0.kind == kind } }
        for kind in active.prefix(3) {
            let relaxed = filters.removing(kind)
            guard let probe = try? await TMDBService.shared.discoverBrowse(relaxed, page: 1),
                  probe.totalResults > 0 else { continue }
            guard !Task.isCancelled else { return }
            recovery = BrowseRecovery(
                kind: kind,
                label: filters.pills.first { $0.kind == kind }?.label ?? "filter",
                count: probe.totalResults
            )
            return
        }
    }

    // MARK: Mutation

    func select(genreId: String) {
        guard filters.genreIds != [genreId] else { return }
        filters.genreIds = [genreId]
        reload()
    }

    func update(_ new: BrowseFilters) {
        guard new != filters else { return }
        filters = new
        reload()
    }

    func remove(_ kind: BrowseFilterPill.Kind) {
        filters = filters.removing(kind)
        reload()
    }
}

// MARK: - View

struct BrowseResultsView: View {
    let genreId: String
    var onSelect: (TMDBResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthViewModel.shared
    @State private var model: BrowseResultsModel
    @State private var showFilters = false
    @State private var showSort = false

    init(genreId: String, onSelect: @escaping (TMDBResult) -> Void) {
        self.genreId = genreId
        self.onSelect = onSelect
        _model = State(wrappedValue: BrowseResultsModel(genreId: genreId, providerIds: []))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            genreRail
            if !model.filters.pills.isEmpty { pillBar }
            countRow
            Divider().overlay(Color.white.opacity(0.07))
            content
        }
        .background(BrandBackground())
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task {
            model.attachProviders(
                StreamingCatalog.ordered(from: auth.selectedServices)
                    .compactMap { StreamingCatalog.tmdbProviderId(for: $0.id) }
            )
            model.reload()
        }
        .sheet(isPresented: $showFilters) {
            BrowseFilterSheet(filters: model.filters) { model.update($0) }
        }
        .sheet(isPresented: $showSort) {
            BrowseSortSheet(sort: model.filters.sort) { sort in
                var next = model.filters
                next.sort = sort
                model.update(next)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to search")

            Text(model.title)
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 8)
    }

    // MARK: Genre rail

    private var genreRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BrowseCatalog.genres) { genre in
                    let isSelected = model.filters.genreIds.contains(genre.id)
                    Button {
                        model.select(genreId: genre.id)
                    } label: {
                        Text(genre.name)
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(isSelected ? .white : Color.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(isSelected ? Color.orange : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 6)
    }

    // MARK: Applied filters

    private var pillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(model.filters.pills) { pill in
                    Button {
                        model.remove(pill.kind)
                    } label: {
                        HStack(spacing: 6) {
                            Text(pill.label)
                                .scaledFont(size: 12, weight: .semibold)
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .opacity(0.6)
                        }
                        .foregroundStyle(pill.accented ? Color.orange : .white)
                        .padding(.leading, 12)
                        .padding(.trailing, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                pill.accented
                                    ? Color.orange.opacity(0.18)
                                    : Color.white.opacity(0.12)
                            )
                        )
                        .overlay(
                            Capsule().stroke(
                                pill.accented ? Color.orange.opacity(0.35) : .clear,
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove filter \(pill.label)")
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 6)
    }

    // MARK: Count + controls

    private var countRow: some View {
        HStack {
            Group {
                if model.isLoading {
                    Text("Loading…")
                } else {
                    Text("\(model.totalResults.formatted()) titles · \(model.filters.sort.label)")
                }
            }
            .scaledFont(size: 12.5, weight: .regular)
            .foregroundStyle(Color.white.opacity(0.5))

            Spacer()

            Button { showSort = true } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sort")

            Button { showFilters = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .overlay(alignment: .topTrailing) {
                        if model.filters.activeCount > 0 {
                            Text("\(model.filters.activeCount)")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Color.navy)
                                .frame(width: 14, height: 14)
                                .background(Circle().fill(Color.orange))
                                .offset(x: 7, y: -6)
                        }
                    }
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .accessibilityLabel("Filters, \(model.filters.activeCount) active")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.results.isEmpty {
            HStack { Spacer(); ProgressView().tint(Color.orange); Spacer() }
                .padding(.top, 48)
            Spacer()
        } else if model.results.isEmpty {
            BrowseEmptyState(
                recovery: model.recovery,
                onRelax: { kind in model.remove(kind) },
                onClearAll: {
                    var cleared = BrowseFilters(providerIds: model.filters.providerIds)
                    cleared.genreIds = model.filters.genreIds
                    cleared.onlyMyServices = false
                    model.update(cleared)
                }
            )
            Spacer()
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView(showsIndicators: false) {
            // Chunked rather than one long LazyVGrid: a lazy grid has no cell
            // spanning, so the full-width ad slot has to sit between grids.
            LazyVStack(spacing: 16) {
                ForEach(Array(model.results.chunked(6).enumerated()), id: \.offset) { chunkIdx, chunk in
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(chunk, id: \.id) { result in
                            BrowsePosterCell(result: result) { onSelect(result) }
                                .onAppear { prefetchIfNeeded(result) }
                        }
                    }

                    if chunk.count == 6 {
                        InlineAdSlotView(
                            slotIndex: chunkIdx,
                            adSource: "browse_grid",
                            sectionKey: "browse_grid_ad",
                            onDismiss: {}
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            if model.isPaging {
                ProgressView().tint(Color.orange).padding(.vertical, 20)
            }

            Color.clear.frame(height: 100)
        }
    }

    /// Pages two rows before the end so the grid never shows a spinner
    /// mid-scroll.
    private func prefetchIfNeeded(_ result: TMDBResult) {
        guard let index = model.results.firstIndex(where: { $0.id == result.id }) else { return }
        if index >= model.results.count - 4 { model.loadNextPage() }
    }
}

// MARK: - Empty state

private struct BrowseEmptyState: View {
    let recovery: BrowseRecovery?
    var onRelax: (BrowseFilterPill.Kind) -> Void
    var onClearAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.white.opacity(0.35))
                .padding(.bottom, 14)

            Text(recovery == nil ? "Nothing matches these filters" : "Nothing matches all of these filters")
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            if let recovery {
                Text("Dropping \(recovery.label) brings back \(recovery.count.formatted()) titles.")
                    .scaledFont(size: 13.5, weight: .regular)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)

                Button {
                    onRelax(recovery.kind)
                } label: {
                    Text("Drop \(recovery.label)")
                        .scaledFont(size: 14, weight: .bold)
                        .foregroundStyle(Color.navy)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.orange))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)
            } else {
                Text("Try widening the filters.")
                    .scaledFont(size: 13.5, weight: .regular)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.bottom, 20)
            }

            Button {
                onClearAll()
            } label: {
                Text("Clear all filters")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 30)
        .padding(.top, 52)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Poster cell

private struct BrowsePosterCell: View {
    let result: TMDBResult
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(2/3, contentMode: .fit)
                    .overlay {
                        RemoteImage(
                            url: result.posterUrl.flatMap(URL.init(string:)),
                            contentMode: .fill
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(result.displayName)
                    .scaledFont(size: 12.5, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(result.isTV ? "Show" : "Movie")
                    if let year = result.year {
                        Circle().fill(Color.white.opacity(0.3)).frame(width: 3, height: 3)
                        Text(String(year))
                    }
                    if let rating = result.voteAverage, rating > 0 {
                        Circle().fill(Color.white.opacity(0.3)).frame(width: 3, height: 3)
                        Text(String(format: "★ %.1f", rating))
                    }
                }
                .scaledFont(size: 11, weight: .regular)
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(result.displayName)
    }
}
