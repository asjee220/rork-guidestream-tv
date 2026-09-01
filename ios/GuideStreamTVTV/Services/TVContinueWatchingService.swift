//
//  TVContinueWatchingService.swift
//  GuideStreamTVTV
//
//  Read-only access to the public.continue_watching view, which feeds the
//  Home "Continue Watching" rail.
//
//  The view is derived from watch_intent_events — the launch-intent rows
//  every platform already writes (deeplink_fired, play_on_device_chosen).
//  Because those rows are keyed by user_id in Supabase, a title launched
//  from the iPhone or the Android app appears here on Apple TV.
//
//  Two things this is NOT:
//    • It is not Apple's Continue Watching. There is no public API to read
//      the TV app's Up Next, and GuideStream plays no video, so it cannot
//      participate in it either.
//    • It is not playback progress. We learn that a title was launched,
//      never how far it got — so the rail carries no percentage or
//      time-remaining, only recency and the service it was opened on.
//
//  The view applies `auth.uid()` itself, so an unauthenticated client gets
//  an empty array rather than someone else's rows. The app never writes here.
//
//  Modelled on TVStreamingReleasesService.swift.
//

import Foundation
import Supabase

@MainActor
@Observable
final class TVContinueWatchingService {
    static let shared = TVContinueWatchingService()

    private init() {}

    /// Columns verified live on public.continue_watching.
    private let selectedColumns = "tmdb_id,media_type,title_name,platform_id,last_action,last_launched_at"

    /// Fetches the caller's recent launches, most recent first. Returns nil
    /// on failure so callers can leave existing rail contents in place, and
    /// an empty array for a signed-out user. Never throws.
    ///
    /// The view already dedupes by title, excludes titles marked watched,
    /// caps the window at 30 days and limits to 20 rows, so there is no
    /// client-side filtering to repeat here.
    func fetch() async -> [TVContinueWatchingRow]? {
        // Guests have no user_id on their events, so the view can never
        // return rows for them. Skip the round trip entirely.
        guard TVAuthViewModel.shared.isAuthenticated else { return [] }
        do {
            let rows: [TVContinueWatchingRow] = try await SupabaseManager.shared.client
                .from("continue_watching")
                .select(selectedColumns)
                .order("last_launched_at", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            return nil
        }
    }
}

// MARK: - Decodable row

nonisolated struct TVContinueWatchingRow: Decodable, Sendable, Identifiable {
    let tmdbId: Int
    /// "tv" or "movie" — resolved server-side from title_names. The launch
    /// events themselves carry no media type, which is why the view joins.
    let mediaType: String
    let titleName: String
    /// The service the title was last opened on. Free-text in the source
    /// events, so it is not guaranteed to match a StreamingCatalog id —
    /// callers must tolerate a miss.
    let platformId: String?
    let lastAction: String
    let lastLaunchedAt: String?

    var id: Int { tmdbId }
    var isTV: Bool { mediaType == "tv" }

    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case mediaType = "media_type"
        case titleName = "title_name"
        case platformId = "platform_id"
        case lastAction = "last_action"
        case lastLaunchedAt = "last_launched_at"
    }
}
