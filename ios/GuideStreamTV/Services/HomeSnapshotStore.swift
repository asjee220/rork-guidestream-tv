import Foundation

/// Last-known Home rails, persisted so the next launch paints real content
/// immediately instead of a shimmer while ~80 requests complete. Only the
/// TMDB-backed rails and their resolved provider names are stored — live
/// sports, creator uploads and anything time-sensitive are refetched.
nonisolated struct HomeSnapshot: Codable, Sendable {
    static let currentVersion = 2

    var version: Int = HomeSnapshot.currentVersion
    var savedAt: Date
    var trending: [TMDBResult]
    var onAir: [TMDBResult]
    var bingeFallback: [TMDBResult]
    var newToday: [TMDBResult]
    var topRated: [TMDBResult]
    var genreShows: [TMDBResult]
    var recommendedShows: [TMDBResult]
    /// Recommended for You — the first rail under the hero. Without it the
    /// snapshot paints Today's Pick first and the page reflows when it lands.
    var recommendedTitles: [RecommendedTitle]
    var newReleases: [StreamingRelease]
    /// tmdbId → provider display name, rebuilt into `Platform` on load.
    var providerNames: [Int: String]
}

/// Disk store for `HomeSnapshot`. Lives in Caches so the OS may evict it;
/// a missing or unreadable file simply means the normal cold load runs.
nonisolated enum HomeSnapshotStore {
    /// Snapshots older than this are ignored rather than shown stale.
    static let maxAge: TimeInterval = 24 * 60 * 60

    private static var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("home_snapshot_v\(HomeSnapshot.currentVersion).json")
    }

    static func load() -> HomeSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snap = try? decoder.decode(HomeSnapshot.self, from: data) else { return nil }
        guard snap.version == HomeSnapshot.currentVersion,
              Date().timeIntervalSince(snap.savedAt) < maxAge,
              !snap.trending.isEmpty else { return nil }
        return snap
    }

    static func save(_ snapshot: HomeSnapshot) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
