//
//  GenreTileGrid.swift
//  GuideStreamTV
//
//  The genre entry point for Search & Browse: artwork tiles, two up.
//
//  A tinted square with an SF Symbol (the Home treatment) does not sell a
//  category — the tile has to show what is inside it. Each tile pulls the top
//  backdrop for its genre once per session and falls back to its brand tint
//  until that lands, so the grid is never empty and never janks.
//

import SwiftUI

// MARK: - Tint

/// Per-genre gradient, used as the tile's resting state and as the fallback
/// behind artwork that has not loaded yet.
enum BrowseTint {
    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    private static let ramps: [String: (UInt32, UInt32)] = [
        "crime":         (0xC0392B, 0x2B0A0E),
        "scifi":         (0x1A6FE8, 0x06111F),
        "horror":        (0x5A1416, 0x050203),
        "anime":         (0x6C3BF5, 0x00C2E0),
        "comedy":        (0x2ECC71, 0x07160E),
        "drama":         (0x8E44AD, 0x120620),
        "action":        (0xF5821F, 0x1C0E02),
        "documentary":   (0x00A99D, 0x02171A),
        "romance":       (0xFF4785, 0x1C0413),
        "international": (0x3D7EA6, 0x050D18)
    ]

    static func colors(for genreId: String) -> [Color] {
        let ramp = ramps[genreId] ?? (0x2D1454, 0x04090F)
        return [rgb(ramp.0), rgb(ramp.1)]
    }
}

// MARK: - Artwork

/// Session cache of one backdrop per genre.
///
/// Ten concurrent discover calls, once, the first time a browse surface
/// appears. Results are held for the life of the process — the tiles are
/// decoration, so a stale-by-an-hour backdrop is not worth a refetch.
@MainActor
@Observable
final class BrowseArtworkStore {
    static let shared = BrowseArtworkStore()

    private(set) var backdrops: [String: String] = [:]
    private var isLoading = false

    private init() {}

    func loadIfNeeded() async {
        guard !isLoading, backdrops.count < BrowseCatalog.genres.count else { return }
        isLoading = true
        defer { isLoading = false }

        let pending = BrowseCatalog.genres.filter { backdrops[$0.id] == nil }
        let fetched = await withTaskGroup(of: (String, String?).self) { group in
            for genre in pending {
                group.addTask {
                    // No provider filter here: the tile should show the genre's
                    // best-known title, not whatever the user happens to have.
                    let filters = BrowseFilters(genreIds: [genre.id], onlyMyServices: false)
                    let page = try? await TMDBService.shared.discoverBrowse(filters)
                    let hero = page?.results.first { $0.backdropPath != nil }
                    return (genre.id, hero?.backdropUrl)
                }
            }
            var out: [String: String] = [:]
            for await (id, url) in group {
                if let url { out[id] = url }
            }
            return out
        }

        backdrops.merge(fetched) { _, new in new }
    }
}

// MARK: - Grid

struct GenreTileGrid: View {
    var onSelect: (BrowseGenre) -> Void

    @State private var artwork = BrowseArtworkStore.shared

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(BrowseCatalog.genres) { genre in
                Button {
                    onSelect(genre)
                } label: {
                    tile(genre)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Browse \(genre.name)")
            }
        }
        .task { await artwork.loadIfNeeded() }
    }

    private func tile(_ genre: BrowseGenre) -> some View {
        let tint = BrowseTint.colors(for: genre.id)
        return ZStack(alignment: .bottomLeading) {
            RemoteImage(
                url: artwork.backdrops[genre.id].flatMap(URL.init(string:)),
                contentMode: .fill,
                fallbackColors: tint
            )
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .clipped()

            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            Text(genre.name)
                .scaledFont(size: 13, weight: .bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                .padding(10)
        }
        .frame(height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Bridge

extension SearchResult {
    /// Adapts a raw discover result to the row/cell model the search surfaces
    /// already render. Browse has no per-title provider lookup — that would be
    /// one request per poster — so the service fields stay neutral.
    init(browseResult item: TMDBResult) {
        self.init(
            id: item.id,
            title: item.displayName,
            isTV: item.isTV,
            posterUrl: item.posterUrl,
            backdropUrl: item.backdropUrl,
            year: item.year,
            genreNames: [],
            serviceName: nil,
            serviceColor: Color(white: 0.18),
            serviceShort: ""
        )
    }
}
