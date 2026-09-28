//
//  MacBrowseArtwork.swift
//  GuideStreamTVMac
//
//  Genre tile tints and backdrops, copied from tvOS TVGenreTileGrid.swift
//  (TVGenreTint + TVBrowseArtworkStore only; the tile views are Mac-specific).
//
import SwiftUI

/// Brand gradient per genre id. Keyed off BrowseCatalog ids, so adding a
/// genre there without adding a gradient here still renders — it falls back
/// to the neutral pair.
enum TVGenreTint {
    static func colors(for id: String) -> [Color] {
        switch id {
        case "crime":         return [Color(red: 0.23, green: 0.12, blue: 0.17), Color(red: 0.56, green: 0.17, blue: 0.28)]
        case "scifi":         return [Color(red: 0.05, green: 0.16, blue: 0.25), Color(red: 0.10, green: 0.44, blue: 0.91)]
        case "horror":        return [Color(red: 0.16, green: 0.05, blue: 0.07), Color(red: 0.70, green: 0.13, blue: 0.17)]
        case "anime":         return [Color(red: 0.17, green: 0.09, blue: 0.25), Color(red: 0.48, green: 0.25, blue: 0.71)]
        case "comedy":        return [Color(red: 0.23, green: 0.17, blue: 0.05), Color(red: 0.88, green: 0.64, blue: 0.16)]
        case "drama":         return [Color(red: 0.07, green: 0.15, blue: 0.21), Color(red: 0.21, green: 0.43, blue: 0.55)]
        case "action":        return [Color(red: 0.23, green: 0.11, blue: 0.03), TVTheme.orange]
        case "documentary":   return [Color(red: 0.06, green: 0.16, blue: 0.14), TVTheme.newsGreen]
        case "romance":       return [Color(red: 0.20, green: 0.07, blue: 0.16), Color(red: 0.76, green: 0.28, blue: 0.56)]
        case "international": return [Color(red: 0.06, green: 0.12, blue: 0.18), Color(red: 0.18, green: 0.36, blue: 0.54)]
        default:              return [TVTheme.surface, TVTheme.surfaceElevated]
        }
    }
}

/// One backdrop per genre, fetched once per launch.
///
/// Ten discover calls, concurrently, the first time the browse surface
/// appears. Held for the life of the process — the tiles are decoration, so
/// a stale-by-an-hour backdrop is not worth a refetch.
@MainActor
@Observable
final class TVBrowseArtworkStore {
    static let shared = TVBrowseArtworkStore()

    /// How many backdrops each genre offers up for the assignment pass. One
    /// is not enough: a title that tops two genres claims both tiles.
    private static let candidateDepth = 8

    private(set) var backdrops: [String: String] = [:]
    private var isLoading = false

    private init() {}

    func loadIfNeeded() async {
        guard !isLoading, backdrops.count < BrowseCatalog.genres.count else { return }
        isLoading = true
        defer { isLoading = false }

        let pending = BrowseCatalog.genres.filter { backdrops[$0.id] == nil }
        let candidates = await withTaskGroup(of: (String, [String]).self) { group in
            for genre in pending {
                group.addTask {
                    // No provider filter: the tile should show the genre's
                    // best-known title, not whatever the viewer subscribes to.
                    let filters = BrowseFilters(genreIds: [genre.id], onlyMyServices: false)
                    let page = try? await TVTMDBService.shared.discoverBrowse(filters)
                    let urls = (page?.results ?? [])
                        .compactMap(\.backdropUrl)
                        .prefix(Self.candidateDepth)
                    return (genre.id, Array(urls))
                }
            }
            var out: [String: [String]] = [:]
            for await (id, urls) in group { out[id] = urls }
            return out
        }

        // Assign in catalogue order rather than completion order, so which
        // tile gets first claim on a shared title does not depend on which
        // network call happened to return first. Each tile takes its most
        // popular backdrop that no earlier tile has taken — Reacher tops both
        // Crime & Thriller and Action, and those two tiles would otherwise
        // show the identical image.
        var used = Set(backdrops.values)
        var resolved: [String: String] = [:]
        for genre in BrowseCatalog.genres {
            guard let options = candidates[genre.id], !options.isEmpty else { continue }
            // If every candidate is spoken for, take the first anyway: a
            // repeated tile still reads better than an empty one.
            let pick = options.first { !used.contains($0) } ?? options[0]
            used.insert(pick)
            resolved[genre.id] = pick
        }

        backdrops.merge(resolved) { _, new in new }
    }
}

