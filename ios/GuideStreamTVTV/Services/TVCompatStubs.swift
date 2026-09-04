//
//  TVCompatStubs.swift
//  GuideStreamTVTV
//
//  Compatibility shims so views shared with the iOS target compile cleanly
//  on tvOS. The tvOS surface area is narrower (no Watchmode lookup, no
//  episode tracker, no streaming-app deeplinking) so these stubs return
//  empty/no-op results while preserving the iOS API signatures.
//

import Foundation
import SwiftUI

// MARK: - StreamsViewModel typealias

typealias StreamsViewModel = TVStreamsViewModel

// MARK: - WatchListView typealias

/// The shared `ProfileView` references `WatchListView()` to push the user's
/// saved titles screen. tvOS has its own native implementation under
/// `TVWatchListView`, so we bridge the iOS name to it.
typealias WatchListView = TVWatchListView

// MARK: - NewEpisodeRow

/// Stub row shape mirrored from the iOS `NewEpisodeRow`. The tvOS
/// target never populates `StreamsViewModel.newEpisodes`, so this only
/// needs the field surface area used by shared views.
struct NewEpisodeRow: Identifiable, Hashable {
    let id: String
    let titleId: String
    let title: String?
    let season: Int?
    let episode: Int?
    let platform: String?
    let posterUrl: String?
    let releasedAt: Date?
    let durationMinutes: Int?
    let isNew: Bool?
}

// MARK: - SocialViewModel stub

/// Slim mirror of the iOS `TitleComment` row. Powered by Supabase on iOS
/// but the tvOS target intentionally short-circuits the social tier so all
/// methods return empty data. Marked `nonisolated` so it is usable across
/// every actor context (mirrors the iOS `TitleComment` declaration).
nonisolated struct TitleComment: Identifiable, Hashable, Sendable {
    let id: String
    let titleId: String
    let userId: String?
    let deviceId: String?
    let displayName: String?
    let initials: String?
    let body: String
    let createdAt: Date?
}

/// Social store wired to Supabase `title_likes` table. Likes are persisted
/// server-side so the tvOS sheet matches the iOS like state.
@MainActor
@Observable
final class SocialViewModel {
    static let shared = SocialViewModel()

    private(set) var likeCounts: [String: Int] = [:]
    private(set) var likedByMe: Set<String> = []
    private(set) var watchedByMe: Set<String> = []
    private(set) var commentCounts: [String: Int] = [:]
    private(set) var commentThreads: [String: [TitleComment]] = [:]
    var loadingComments: Set<String> = []
    var postingComment: Set<String> = []

    nonisolated private struct LikeRow: Decodable {
        let titleId: String
        enum CodingKeys: String, CodingKey { case titleId = "title_id" }
    }

    /// Concrete `Encodable` payload for inserting a like row. Using a struct
    /// avoids the `any Encodable` existential issue with dictionary literals.
    private struct LikeInsertPayload: Encodable {
        let title_id: String
        let device_id: String
        let user_id: String?
        let media_type: String?
        let tmdb_id: Int?
    }

    nonisolated private struct WatchedRow: Decodable {
        let titleId: String
        enum CodingKeys: String, CodingKey { case titleId = "title_id" }
    }

    /// Concrete `Encodable` payload for inserting a watched row. Mirrors
    /// `LikeInsertPayload` but also carries the series `title_name`.
    private struct WatchedInsertPayload: Encodable {
        let title_id: String
        let device_id: String
        let user_id: String?
        let title_name: String?
        let media_type: String?
        let tmdb_id: Int?
    }

    private init() {}

    func likes(_ titleId: String) -> Int { likeCounts[titleId] ?? 0 }
    func isLiked(_ titleId: String) -> Bool { likedByMe.contains(titleId) }
    func isWatched(_ titleId: String) -> Bool { watchedByMe.contains(titleId) }
    func commentTotal(_ titleId: String) -> Int { commentCounts[titleId] ?? 0 }
    func thread(_ titleId: String) -> [TitleComment] { commentThreads[titleId] ?? [] }

    func isLoadingComments(_ titleId: String) -> Bool {
        loadingComments.contains(titleId)
    }

    func isPostingComment(_ titleId: String) -> Bool {
        postingComment.contains(titleId)
    }

    // MARK: - Likes

    /// Queries `title_likes` for the current owner and sets `likedByMe`.
    func refreshCounts(titleId: String) async {
        let deviceId = TVDeviceIdentity.shared.deviceId
        let userId = TVAuthViewModel.shared.currentUser?.id.uuidString

        var query = TVSupabaseManager.shared.client
            .from("title_likes")
            .select("title_id")
            .eq("title_id", value: titleId)

        if let userId {
            query = query.eq("user_id", value: userId)
        } else {
            query = query.eq("device_id", value: deviceId).filter("user_id", operator: "is", value: "null")
        }

        do {
            let rows: [LikeRow] = try await query.execute().value
            if rows.isEmpty {
                likedByMe.remove(titleId)
            } else {
                likedByMe.insert(titleId)
            }
        } catch {
            // Silently keep current state on failure.
        }

        var watchedQuery = TVSupabaseManager.shared.client
            .from("title_watched")
            .select("title_id")
            .eq("title_id", value: titleId)

        if let userId {
            watchedQuery = watchedQuery.eq("user_id", value: userId)
        } else {
            watchedQuery = watchedQuery.eq("device_id", value: deviceId).filter("user_id", operator: "is", value: "null")
        }

        do {
            let rows: [WatchedRow] = try await watchedQuery.execute().value
            if rows.isEmpty {
                watchedByMe.remove(titleId)
            } else {
                watchedByMe.insert(titleId)
            }
        } catch {
            // Silently keep current state on failure.
        }
    }

    /// Loads every `title_watched` row owned by the current user/device in a
    /// single query and replaces `watchedByMe`. Display-only: used by the
    /// Watch List to show the eye badge on saved titles already marked
    /// watched. Never writes to `title_watched`.
    func loadAllWatched() async {
        let deviceId = TVDeviceIdentity.shared.deviceId
        let userId = TVAuthViewModel.shared.currentUser?.id.uuidString

        var query = TVSupabaseManager.shared.client
            .from("title_watched")
            .select("title_id")

        if let userId {
            query = query.eq("user_id", value: userId)
        } else {
            query = query.eq("device_id", value: deviceId).filter("user_id", operator: "is", value: "null")
        }

        do {
            let rows: [WatchedRow] = try await query.execute().value
            watchedByMe = Set(rows.map { $0.titleId })
        } catch {
            // Silently keep current state on failure.
        }
    }

    /// Optimistically flips the series-level watched flag, then writes through
    /// to `title_watched` best-effort. Mirrors `toggleLike`. One tap marks the
    /// whole series — never per-episode.
    func toggleWatched(titleId: String, titleName: String? = nil, mediaType: String? = nil, tmdbId: Int? = nil) async {
        let wasWatched = watchedByMe.contains(titleId)

        // Optimistic flip
        if wasWatched {
            watchedByMe.remove(titleId)
        } else {
            watchedByMe.insert(titleId)
        }

        let deviceId = TVDeviceIdentity.shared.deviceId
        let userId = TVAuthViewModel.shared.currentUser?.id.uuidString

        do {
            if wasWatched {
                // Un-watch — delete the row
                var query = TVSupabaseManager.shared.client
                    .from("title_watched")
                    .delete()
                    .eq("title_id", value: titleId)
                if let userId {
                    query = query.eq("user_id", value: userId)
                } else {
                    query = query.eq("device_id", value: deviceId)
                }
                _ = try await query.execute()
            } else {
                // Watched — insert a row
                let payload = WatchedInsertPayload(
                    title_id: titleId,
                    device_id: deviceId,
                    user_id: userId,
                    title_name: titleName,
                    media_type: mediaType,
                    tmdb_id: tmdbId
                )
                _ = try await TVSupabaseManager.shared.client
                    .from("title_watched")
                    .insert(payload)
                    .execute()
            }
        } catch {
            // Swallow — optimistic state wins.
        }

        // Log the intent
        WatchIntentLogger.shared.log(
            eventType: .watchedToggled,
            titleId: titleId
        )
    }

    /// Optimistically flips local state, then writes through to Supabase
    /// best-effort. Failures never revert the optimistic flip.
    func toggleLike(titleId: String, mediaType: String? = nil, tmdbId: Int? = nil) async {
        let wasLiked = likedByMe.contains(titleId)

        // Optimistic flip
        if wasLiked {
            likedByMe.remove(titleId)
        } else {
            likedByMe.insert(titleId)
        }

        let deviceId = TVDeviceIdentity.shared.deviceId
        let userId = TVAuthViewModel.shared.currentUser?.id.uuidString

        do {
            if wasLiked {
                // Unlike — delete the row
                var query = TVSupabaseManager.shared.client
                    .from("title_likes")
                    .delete()
                    .eq("title_id", value: titleId)
                if let userId {
                    query = query.eq("user_id", value: userId)
                } else {
                    query = query.eq("device_id", value: deviceId)
                }
                _ = try await query.execute()
            } else {
                // Like — insert a row
                let payload = LikeInsertPayload(
                    title_id: titleId,
                    device_id: deviceId,
                    user_id: userId,
                    media_type: mediaType,
                    tmdb_id: tmdbId
                )
                _ = try await TVSupabaseManager.shared.client
                    .from("title_likes")
                    .insert(payload)
                    .execute()
            }
        } catch {
            // Swallow — optimistic state wins.
        }

        // Log the intent
        WatchIntentLogger.shared.log(
            eventType: .trailerLiked,
            titleId: titleId
        )
    }

    func loadComments(titleId: String) async {}
    func postComment(titleId: String, body: String) async -> Bool { false }

    static func initials(firstName: String?, lastName: String?, displayName: String?) -> String {
        if let first = firstName?.first, let last = lastName?.first {
            return "\(first)\(last)".uppercased()
        }
        if let name = displayName, !name.isEmpty {
            let parts = name.split(separator: " ").prefix(2)
            return parts.compactMap { $0.first }.map { String($0) }.joined().uppercased()
        }
        return "?"
    }
}

// MARK: - Watchmode stubs

/// Stub of the iOS `WatchmodeSource`. Real streaming-source lookups are
/// disabled on tvOS so this only exists to satisfy types in shared views.
nonisolated struct WatchmodeSource: Hashable, Sendable, Identifiable {
    let sourceId: Int
    let name: String
    let type: String
    let region: String?
    let iosUrl: String?
    let androidUrl: String?
    let webUrl: String?
    let format: String?
    let endDate: String?
    let tvosUrl: String?
    let price: Double?

    var id: String { "\(sourceId)-\(format ?? "")-\(region ?? "")" }
}

nonisolated struct WatchmodeTitleDetail: Sendable {
    let id: String
    let title: String
    let plotOverview: String?
    let sources: [WatchmodeSource]?
    let genreNames: [String]
    let userRating: Double?
    let year: Int?

    init(
        id: String,
        title: String,
        plotOverview: String? = nil,
        sources: [WatchmodeSource]? = nil,
        genreNames: [String] = [],
        userRating: Double? = nil,
        year: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.plotOverview = plotOverview
        self.sources = sources
        self.genreNames = genreNames
        self.userRating = userRating
        self.year = year
    }
}

/// No-op Watchmode service. Always returns nil so shared views fall back
/// to TMDB-provided overviews and the "Streaming services" placeholder.
nonisolated struct WatchmodeService {
    static let shared = WatchmodeService()

    func watchmodeId(forTMDBId tmdbId: Int, isTV: Bool) async throws -> String? { nil }
    func titleDetail(titleId: String) async throws -> WatchmodeTitleDetail {
        WatchmodeTitleDetail(id: titleId, title: "")
    }
}

// MARK: - Streaming helpers

/// No-op deeplinker. tvOS apps can't open another device's streaming app,
/// so this is a quiet stub for shared sheets. Overloads cover every call
/// shape the iOS source uses (`platform/title`, plus optional `tmdbId`,
/// `isTV`, and/or `titleSlug`).
enum StreamingDeepLinker {
    static func open(platform: String, title: String, tmdbId: Int?, isTV: Bool) {}
    static func open(platform: String, title: String, tmdbId: Int?, isTV: Bool, titleSlug: String) {}
    static func open(platform: String, title: String, titleSlug: String) {}
}

/// Stub streaming-service catalog used by onboarding + the home services
/// pill. Provides a static list so shared views render without crashing.
struct StreamingService: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
}

enum StreamingCatalog {
    /// The phone's catalogue, in full. It used to be twelve services while
    /// iOS carried 177, so most of what a viewer subscribes to could not be
    /// picked here at all — and the ids drifted too: Max is "hbo" on iOS and
    /// was "max" here, so a Max subscription chosen on the phone did not read
    /// as selected on the TV. Generated from
    /// ios/GuideStreamTV/Models/StreamingService.swift; `color` is that
    /// file's `glow`, the brand accent, since the marks carry their own
    /// backgrounds. Regenerate both lists together when the phone's changes.
    static let all: [StreamingService] = [
        StreamingService(id: "netflix", name: "Netflix", color: Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255)),
        StreamingService(id: "prime", name: "Prime Video", color: Color(red: 0x00/255, green: 0xA8/255, blue: 0xE1/255)),
        StreamingService(id: "disney", name: "Disney+", color: Color(red: 0x11/255, green: 0x3C/255, blue: 0xCF/255)),
        StreamingService(id: "hbo", name: "Max", color: Color(red: 0x00/255, green: 0x55/255, blue: 0xFF/255)),
        StreamingService(id: "appletv", name: "Apple TV+", color: Color.white),
        StreamingService(id: "paramount", name: "Paramount+", color: Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255)),
        StreamingService(id: "hulu", name: "Hulu", color: Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255)),
        StreamingService(id: "peacock", name: "Peacock", color: Color(red: 0xFF/255, green: 0x66/255, blue: 0x00/255)),
        StreamingService(id: "crunchyroll", name: "Crunchyroll", color: Color(red: 0xF4/255, green: 0x7B/255, blue: 0x20/255)),
        StreamingService(id: "espn", name: "ESPN+", color: Color(red: 0xD0/255, green: 0x21/255, blue: 0x31/255)),
        StreamingService(id: "discovery", name: "Discovery+", color: Color(red: 0x00/255, green: 0x9A/255, blue: 0xFF/255)),
        StreamingService(id: "mgm", name: "MGM+", color: Color(red: 0xC7/255, green: 0xA1/255, blue: 0x5A/255)),
        StreamingService(id: "starz", name: "Starz", color: Color(red: 0xFF/255, green: 0xC8/255, blue: 0x1E/255)),
        StreamingService(id: "showtime", name: "Showtime", color: Color(red: 0xD8/255, green: 0x00/255, blue: 0x00/255)),
        StreamingService(id: "amc", name: "AMC+", color: Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255)),
        StreamingService(id: "mubi", name: "Mubi", color: Color.white),
        StreamingService(id: "dazn", name: "DAZN", color: Color(red: 0xF4/255, green: 0x00/255, blue: 0x29/255)),
        StreamingService(id: "youtubetv", name: "YouTube TV", color: Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255)),
        StreamingService(id: "hotstar", name: "Hotstar", color: Color(red: 0x18/255, green: 0x47/255, blue: 0xFF/255)),
        StreamingService(id: "zee5", name: "Zee5", color: Color(red: 0xFF/255, green: 0x18/255, blue: 0xA1/255)),
        StreamingService(id: "sonyliv", name: "SonyLIV", color: Color(red: 0xFF/255, green: 0x66/255, blue: 0x00/255)),
        StreamingService(id: "sky", name: "Sky", color: Color(red: 0x00/255, green: 0xA0/255, blue: 0xE1/255)),
        StreamingService(id: "nowtv", name: "NOW", color: Color(red: 0x00/255, green: 0xB7/255, blue: 0xFF/255)),
        StreamingService(id: "skyshowtime", name: "SkyShowtime", color: Color(red: 0xFF/255, green: 0x00/255, blue: 0x73/255)),
        StreamingService(id: "canalplus", name: "Canal+", color: Color.white),
        StreamingService(id: "movistar", name: "Movistar+", color: Color(red: 0x5F/255, green: 0xD0/255, blue: 0xE8/255)),
        StreamingService(id: "stan", name: "Stan", color: Color(red: 0x00/255, green: 0xD4/255, blue: 0xFF/255)),
        StreamingService(id: "binge", name: "Binge", color: Color(red: 0xFF/255, green: 0x29/255, blue: 0x00/255)),
        StreamingService(id: "foxtel", name: "Foxtel Now", color: Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255)),
        StreamingService(id: "kayo", name: "Kayo Sports", color: Color(red: 0x18/255, green: 0xE0/255, blue: 0xC8/255)),
        StreamingService(id: "globoplay", name: "Globoplay", color: Color(red: 0xFF/255, green: 0x29/255, blue: 0x66/255)),
        StreamingService(id: "vix", name: "ViX", color: Color(red: 0xFF/255, green: 0xC0/255, blue: 0x00/255)),
        StreamingService(id: "claro", name: "Clarovideo", color: Color(red: 0xFF/255, green: 0x3B/255, blue: 0x3B/255)),
        StreamingService(id: "crave", name: "Crave", color: Color(red: 0x00/255, green: 0xC2/255, blue: 0xA8/255)),
        StreamingService(id: "tving", name: "TVING", color: Color(red: 0xFF/255, green: 0x15/255, blue: 0x60/255)),
        StreamingService(id: "wavve", name: "wavve", color: Color(red: 0x3B/255, green: 0x57/255, blue: 0xFF/255)),
        StreamingService(id: "watcha", name: "Watcha", color: Color(red: 0xFF/255, green: 0x05/255, blue: 0x58/255)),
        StreamingService(id: "unext", name: "U-NEXT", color: Color(red: 0xFF/255, green: 0xFF/255, blue: 0xFF/255)),
        StreamingService(id: "wow", name: "WOW", color: Color(red: 0x00/255, green: 0xE0/255, blue: 0xC8/255)),
        StreamingService(id: "rtlplus", name: "RTL+", color: Color(red: 0xE4/255, green: 0x00/255, blue: 0x3A/255)),
        StreamingService(id: "joyn", name: "Joyn", color: Color(red: 0x00/255, green: 0xE0/255, blue: 0xB0/255)),
        StreamingService(id: "videoland", name: "Videoland", color: Color(red: 0xFF/255, green: 0x4B/255, blue: 0x00/255)),
        StreamingService(id: "tf1plus", name: "TF1+", color: Color(red: 0x3B/255, green: 0x7B/255, blue: 0xFF/255)),
        StreamingService(id: "m6plus", name: "M6+", color: Color(red: 0xE4/255, green: 0x00/255, blue: 0x7A/255)),
        StreamingService(id: "viaplay", name: "Viaplay", color: Color(red: 0xDB/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "magentatv", name: "MagentaTV", color: Color(red: 0x96/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "timvision", name: "Timvision", color: Color(red: 0xEC/255, green: 0x9E/255, blue: 0x45/255)),
        StreamingService(id: "atresplayer", name: "Atres Player", color: Color(red: 0x45/255, green: 0xA9/255, blue: 0xEC/255)),
        StreamingService(id: "sfrplay", name: "SFR Play", color: Color(red: 0x69/255, green: 0x45/255, blue: 0xEC/255)),
        StreamingService(id: "nlziet", name: "NLZIET", color: Color(red: 0xEC/255, green: 0x7D/255, blue: 0x45/255)),
        StreamingService(id: "citytv", name: "Citytv+", color: Color(red: 0xA4/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "clarotv", name: "Claro tv+", color: Color(red: 0x45/255, green: 0xA4/255, blue: 0xEC/255)),
        StreamingService(id: "tvaplus", name: "TVA+", color: Color(red: 0x45/255, green: 0xD6/255, blue: 0xEC/255)),
        StreamingService(id: "noovo", name: "Noovo", color: Color(red: 0x45/255, green: 0xB7/255, blue: 0xEC/255)),
        StreamingService(id: "clubillico", name: "Club Illico", color: Color(red: 0xEC/255, green: 0x56/255, blue: 0x45/255)),
        StreamingService(id: "rds", name: "RDS", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0x58/255)),
        StreamingService(id: "skygo", name: "Sky Go", color: Color(red: 0x6F/255, green: 0x45/255, blue: 0xEC/255)),
        StreamingService(id: "virgintv", name: "Virgin TV GO", color: Color(red: 0x45/255, green: 0x69/255, blue: 0xEC/255)),
        StreamingService(id: "allente", name: "Allente", color: Color(red: 0x7A/255, green: 0x45/255, blue: 0xEC/255)),
        StreamingService(id: "strim", name: "Strim", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0xBD/255)),
        StreamingService(id: "ruutu", name: "Ruutu", color: Color(red: 0x7F/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "tele2", name: "Tele2 Play", color: Color(red: 0x45/255, green: 0xEC/255, blue: 0x66/255)),
        StreamingService(id: "tv4play", name: "TV4 Play", color: Color(red: 0x99/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "tv2", name: "TV 2", color: Color(red: 0x66/255, green: 0x45/255, blue: 0xEC/255)),
        StreamingService(id: "bet", name: "BET+", color: Color(red: 0xB1/255, green: 0x4E/255, blue: 0xFF/255)),
        StreamingService(id: "philo", name: "Philo", color: Color(red: 0x7B/255, green: 0x2F/255, blue: 0xF7/255)),
        StreamingService(id: "fubo", name: "Fubo", color: Color(red: 0xEC/255, green: 0x18/255, blue: 0x40/255)),
        StreamingService(id: "sling", name: "Sling TV", color: Color(red: 0xFF/255, green: 0x73/255, blue: 0x00/255)),
        StreamingService(id: "directv", name: "DIRECTV Stream", color: Color(red: 0x00/255, green: 0xA0/255, blue: 0xE1/255)),
        StreamingService(id: "fox", name: "FOX One", color: Color(red: 0x00/255, green: 0x89/255, blue: 0xCF/255)),
        StreamingService(id: "hayu", name: "Hayu", color: Color(red: 0x00/255, green: 0xD2/255, blue: 0xA0/255)),
        StreamingService(id: "britbox", name: "BritBox", color: Color(red: 0xFF/255, green: 0x4B/255, blue: 0x9C/255)),
        StreamingService(id: "britboxuk", name: "BritBox UK", color: Color(red: 0x45/255, green: 0x61/255, blue: 0xEC/255)),
        StreamingService(id: "acorntv", name: "Acorn TV", color: Color(red: 0x6E/255, green: 0xC1/255, blue: 0x6E/255)),
        StreamingService(id: "hallmark", name: "Hallmark+", color: Color(red: 0x9B/255, green: 0x7F/255, blue: 0xD4/255)),
        StreamingService(id: "criterion", name: "Criterion", color: Color(red: 0xE8/255, green: 0xE8/255, blue: 0xE8/255)),
        StreamingService(id: "shudder", name: "Shudder", color: Color(red: 0x9A/255, green: 0x00/255, blue: 0xFF/255)),
        StreamingService(id: "hidive", name: "HiDive", color: Color(red: 0x00/255, green: 0xC2/255, blue: 0xFF/255)),
        StreamingService(id: "kanopy", name: "Kanopy", color: Color(red: 0xFF/255, green: 0x3B/255, blue: 0x4E/255)),
        StreamingService(id: "hoopla", name: "Hoopla", color: Color(red: 0x00/255, green: 0xA6/255, blue: 0xCE/255)),
        StreamingService(id: "rakutenviki", name: "Viki", color: Color(red: 0xBC/255, green: 0x00/255, blue: 0x6C/255)),
        StreamingService(id: "bfiplayer", name: "BFI Player", color: Color(red: 0xD6/255, green: 0x45/255, blue: 0xEC/255)),
        StreamingService(id: "mlb", name: "MLB.TV", color: Color(red: 0xBF/255, green: 0x0D/255, blue: 0x3E/255)),
        StreamingService(id: "wnba", name: "WNBA League Pass", color: Color(red: 0xFF/255, green: 0x7A/255, blue: 0x00/255)),
        StreamingService(id: "tennis", name: "Tennis Channel", color: Color(red: 0xC6/255, green: 0xFF/255, blue: 0x00/255)),
        StreamingService(id: "bein", name: "beIN Sports", color: Color(red: 0x6E/255, green: 0x1E/255, blue: 0xFF/255)),
        StreamingService(id: "f1tv", name: "F1 TV", color: Color(red: 0xE1/255, green: 0x06/255, blue: 0x00/255)),
        StreamingService(id: "optus", name: "Optus Sport", color: Color(red: 0x7E/255, green: 0xE0/255, blue: 0x00/255)),
        StreamingService(id: "premier", name: "Premier Sports", color: Color(red: 0xFF/255, green: 0xC0/255, blue: 0x00/255)),
        StreamingService(id: "skysports", name: "Sky Sports", color: Color(red: 0x00/255, green: 0xA0/255, blue: 0xE1/255)),
        StreamingService(id: "tsn", name: "TSN", color: Color(red: 0xE4/255, green: 0x00/255, blue: 0x2B/255)),
        StreamingService(id: "sportsnet", name: "Sportsnet+", color: Color(red: 0x00/255, green: 0x57/255, blue: 0xB8/255)),
        StreamingService(id: "nwsl", name: "NWSL+", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0x85/255)),
        StreamingService(id: "florugby", name: "Flo Rugby", color: Color(red: 0x93/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "kleague", name: "K League TV", color: Color(red: 0x45/255, green: 0x8D/255, blue: 0xEC/255)),
        StreamingService(id: "curiosity", name: "Curiosity", color: Color(red: 0x00/255, green: 0xC2/255, blue: 0xFF/255)),
        StreamingService(id: "tubi", name: "Tubi", color: Color(red: 0xFF/255, green: 0x40/255, blue: 0x40/255)),
        StreamingService(id: "pluto", name: "Pluto TV", color: Color(red: 0xFF/255, green: 0xE0/255, blue: 0x36/255)),
        StreamingService(id: "roku", name: "Roku Channel", color: Color(red: 0xB4/255, green: 0x53/255, blue: 0xFF/255)),
        StreamingService(id: "plex", name: "Plex", color: Color(red: 0xE5/255, green: 0xA0/255, blue: 0x17/255)),
        StreamingService(id: "xumo", name: "Xumo Play", color: Color(red: 0x8B/255, green: 0x2C/255, blue: 0xF5/255)),
        StreamingService(id: "samsungtvplus", name: "Samsung TV Plus", color: Color(red: 0x4A/255, green: 0x6C/255, blue: 0xF7/255)),
        StreamingService(id: "freevee", name: "Amazon Freevee", color: Color(red: 0x00/255, green: 0xA8/255, blue: 0xE1/255)),
        StreamingService(id: "crackle", name: "Crackle", color: Color(red: 0xFF/255, green: 0xA8/255, blue: 0x00/255)),
        StreamingService(id: "popcornflix", name: "Popcornflix", color: Color(red: 0xFF/255, green: 0x2E/255, blue: 0x00/255)),
        StreamingService(id: "cineverse", name: "Cineverse", color: Color(red: 0x00/255, green: 0xD0/255, blue: 0xC0/255)),
        StreamingService(id: "ondemandkorea", name: "OnDemandKorea", color: Color(red: 0x3E/255, green: 0x7B/255, blue: 0xFA/255)),
        StreamingService(id: "mercado", name: "Mercado Play", color: Color(red: 0xFF/255, green: 0xE6/255, blue: 0x00/255)),
        StreamingService(id: "fawesome", name: "Fawesome", color: Color(red: 0x69/255, green: 0x45/255, blue: 0xEC/255)),
        StreamingService(id: "youtube", name: "YouTube", color: Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255)),
        StreamingService(id: "bbciplayer", name: "BBC iPlayer", color: Color(red: 0xFB/255, green: 0xB0/255, blue: 0x32/255)),
        StreamingService(id: "itvx", name: "ITVX", color: Color(red: 0xFF/255, green: 0xC0/255, blue: 0x00/255)),
        StreamingService(id: "channel4", name: "Channel 4", color: Color(red: 0xAA/255, green: 0xFF/255, blue: 0x00/255)),
        StreamingService(id: "my5", name: "My5", color: Color(red: 0xEC/255, green: 0xB7/255, blue: 0x45/255)),
        StreamingService(id: "uktv", name: "UKTV Play", color: Color(red: 0x45/255, green: 0x66/255, blue: 0xEC/255)),
        StreamingService(id: "7plus", name: "7plus", color: Color(red: 0x45/255, green: 0xEC/255, blue: 0xE4/255)),
        StreamingService(id: "9now", name: "9Now", color: Color(red: 0xEC/255, green: 0x53/255, blue: 0x45/255)),
        StreamingService(id: "tenplay", name: "tenplay", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0x6F/255)),
        StreamingService(id: "iview", name: "ABC iview", color: Color(red: 0x9E/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "sbs", name: "SBS On Demand", color: Color(red: 0x45/255, green: 0xB4/255, blue: 0xEC/255)),
        StreamingService(id: "tvnz", name: "TVNZ+", color: Color(red: 0xEC/255, green: 0x7F/255, blue: 0x45/255)),
        StreamingService(id: "ctv", name: "CTV", color: Color(red: 0x4D/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "cbcgem", name: "CBC Gem", color: Color(red: 0xEC/255, green: 0x4D/255, blue: 0x45/255)),
        StreamingService(id: "globaltv", name: "Global TV", color: Color(red: 0xEC/255, green: 0x6F/255, blue: 0x45/255)),
        StreamingService(id: "zdf", name: "ZDF", color: Color(red: 0x66/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "ardplus", name: "ARD Plus", color: Color(red: 0xEC/255, green: 0x58/255, blue: 0x45/255)),
        StreamingService(id: "toggo", name: "Toggo", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0x93/255)),
        StreamingService(id: "ae", name: "A&E", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0x5B/255)),
        StreamingService(id: "hgtv", name: "HGTV", color: Color(red: 0xC8/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "usa", name: "USA", color: Color(red: 0xAC/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "syfy", name: "Syfy", color: Color(red: 0x45/255, green: 0x85/255, blue: 0xEC/255)),
        StreamingService(id: "mtv", name: "MTV", color: Color(red: 0xEC/255, green: 0x58/255, blue: 0x45/255)),
        StreamingService(id: "vh1", name: "VH1", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0xA1/255)),
        StreamingService(id: "tvland", name: "TV Land", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0x6F/255)),
        StreamingService(id: "lifetime", name: "Lifetime", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0xDE/255)),
        StreamingService(id: "foodnetwork", name: "Food Network", color: Color(red: 0x45/255, green: 0xEC/255, blue: 0xEC/255)),
        StreamingService(id: "travel", name: "Travel Channel", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0xE9/255)),
        StreamingService(id: "national", name: "National Geographic", color: Color(red: 0x45/255, green: 0x7A/255, blue: 0xEC/255)),
        StreamingService(id: "investigation", name: "Investigation Discovery", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0x56/255)),
        StreamingService(id: "history", name: "The History Channel", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0xE1/255)),
        StreamingService(id: "cartoon", name: "Cartoon Network", color: Color(red: 0xEC/255, green: 0x50/255, blue: 0x45/255)),
        StreamingService(id: "adultswim", name: "Adult Swim", color: Color(red: 0xEC/255, green: 0xDB/255, blue: 0x45/255)),
        StreamingService(id: "freeform", name: "Freeform", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0xCB/255)),
        StreamingService(id: "cw", name: "The CW", color: Color(red: 0x45/255, green: 0x53/255, blue: 0xEC/255)),
        StreamingService(id: "cbs", name: "CBS", color: Color(red: 0xA9/255, green: 0x45/255, blue: 0xEC/255)),
        StreamingService(id: "nbc", name: "NBC", color: Color(red: 0xEC/255, green: 0x9B/255, blue: 0x45/255)),
        StreamingService(id: "foxnet", name: "FOX", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0xA1/255)),
        StreamingService(id: "pbs", name: "PBS", color: Color(red: 0x45/255, green: 0xEC/255, blue: 0xCD/255)),
        StreamingService(id: "pbskids", name: "PBS Kids", color: Color(red: 0x50/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "bbcamerica", name: "BBC America", color: Color(red: 0xB2/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "wowpresents", name: "WOW Presents Plus", color: Color(red: 0x45/255, green: 0x9B/255, blue: 0xEC/255)),
        StreamingService(id: "kocowa", name: "Kocowa", color: Color(red: 0xEC/255, green: 0xBA/255, blue: 0x45/255)),
        StreamingService(id: "sunnxt", name: "Sun Nxt", color: Color(red: 0xA4/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "hungama", name: "Hungama Play", color: Color(red: 0x45/255, green: 0x90/255, blue: 0xEC/255)),
        StreamingService(id: "arrow", name: "Arrow Video Channel", color: Color(red: 0xEC/255, green: 0xC8/255, blue: 0x45/255)),
        StreamingService(id: "fandor", name: "Fandor", color: Color(red: 0x45/255, green: 0x93/255, blue: 0xEC/255)),
        StreamingService(id: "mhz", name: "MHz Choice", color: Color(red: 0x45/255, green: 0xEC/255, blue: 0xD0/255)),
        StreamingService(id: "topic", name: "Topic", color: Color(red: 0xEC/255, green: 0x9B/255, blue: 0x45/255)),
        StreamingService(id: "sundance", name: "SundanceNow Doc Club", color: Color(red: 0xA1/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "darkmatter", name: "Darkmatter TV", color: Color(red: 0x64/255, green: 0x45/255, blue: 0xEC/255)),
        StreamingService(id: "flixpremiere", name: "Flix Premiere", color: Color(red: 0x45/255, green: 0xEC/255, blue: 0xEC/255)),
        StreamingService(id: "flixfling", name: "FlixFling", color: Color(red: 0x45/255, green: 0x48/255, blue: 0xEC/255)),
        StreamingService(id: "animation", name: "Animation Digital Network", color: Color(red: 0xEC/255, green: 0x61/255, blue: 0x45/255)),
        StreamingService(id: "wwe", name: "WWE Network", color: Color(red: 0x96/255, green: 0xEC/255, blue: 0x45/255)),
        StreamingService(id: "hollywoodsuite", name: "Hollywood Suite", color: Color(red: 0x6F/255, green: 0x45/255, blue: 0xEC/255)),
        StreamingService(id: "guidedoc", name: "GuideDoc", color: Color(red: 0x45/255, green: 0xEC/255, blue: 0xD6/255)),
        StreamingService(id: "beamafilm", name: "Beamafilm", color: Color(red: 0xEC/255, green: 0xDB/255, blue: 0x45/255)),
        StreamingService(id: "filmin", name: "FILMIN", color: Color(red: 0xEC/255, green: 0xE4/255, blue: 0x45/255)),
        StreamingService(id: "neon", name: "Neon TV", color: Color(red: 0x45/255, green: 0x93/255, blue: 0xEC/255)),
        StreamingService(id: "shoutfactory", name: "Shout! Factory TV", color: Color(red: 0xE1/255, green: 0x45/255, blue: 0xEC/255)),
        StreamingService(id: "fod", name: "FOD", color: Color(red: 0xEC/255, green: 0x45/255, blue: 0xD9/255)),
        StreamingService(id: "jiocinema", name: "JioCinema", color: Color(red: 0xFF/255, green: 0x60/255, blue: 0x33/255)),
        StreamingService(id: "raiplay", name: "RaiPlay", color: Color(red: 0x00/255, green: 0xB7/255, blue: 0xFF/255)),
        StreamingService(id: "iqiyi", name: "iQIYI", color: Color(red: 0x00/255, green: 0xF0/255, blue: 0x82/255)),
        StreamingService(id: "wetv", name: "WeTV", color: Color(red: 0xFF/255, green: 0x84/255, blue: 0x21/255)),
        StreamingService(id: "viu", name: "Viu", color: Color(red: 0xFF/255, green: 0xCC/255, blue: 0x00/255)),
        StreamingService(id: "abema", name: "ABEMA", color: Color(red: 0x00/255, green: 0xE6/255, blue: 0x66/255))
    ]

    /// Returns the catalog filtered + ordered by `selectedIds`. Matches the
    /// iOS API so shared views compile.
    static func ordered(from selectedIds: Set<String>) -> [StreamingService] {
        all.filter { selectedIds.contains($0.id) }
    }
}

// MARK: - Service typealiases

typealias TMDBService = TVTMDBService
typealias SportsService = TVSportsService

// MARK: - TMDBService stub extensions

/// Methods used by shared views that aren't part of the lean tvOS
/// `TVTMDBService` surface. They all fall back gracefully.
extension TVTMDBService {
    /// No-op for tvOS — returns an empty list so the "What's new today" rail
    /// is hidden when the data isn't available.
    func getNewToday() async throws -> [TVTMDBResult] { [] }

    /// Same fallback as `getOnTheAir()` so the "Binge worthy" rail still
    /// has something to render on tvOS.
    func getDiscoverEnded() async throws -> [TVTMDBResult] {
        try await getOnTheAir()
    }

    /// Show detail lookup not wired up on tvOS — shared views render with
    /// the data they already have.
    func getTVDetail(tmdbId: Int) async throws -> TMDBTVDetail? { nil }

    // `getSeason` is no longer a stub — it is implemented for real in
    // TVTMDBService so the title detail screen can show an episode rail.
    // Do not re-add a stub here; it would shadow the working call.
}

// MARK: - Minimal TMDB detail / season stubs

/// Slim mirror of the iOS `TMDBTVDetail` — only the fields touched by
/// shared views need to exist for compilation.
nonisolated struct TMDBTVDetail: Sendable, Decodable {
    let id: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let numberOfSeasons: Int?
    let firstAirDate: String?
    let voteAverage: Double?
    let status: String?
    let genres: [TMDBGenre]?
    let seasons: [TMDBSeasonSummary]?

    var displayName: String { name ?? "" }
    var posterUrl: String? { TVTMDBImage.url(posterPath, size: .poster500) }
    var backdropUrl: String? { TVTMDBImage.url(backdropPath, size: .original) }
    var genreNames: [String] { (genres ?? []).map { $0.name } }
    var year: Int? {
        guard let firstAirDate, firstAirDate.count >= 4 else { return nil }
        return Int(firstAirDate.prefix(4))
    }

    enum CodingKeys: String, CodingKey {
        case id, name, overview, status, genres, seasons
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case numberOfSeasons = "number_of_seasons"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
    }
}

nonisolated struct TMDBGenre: Sendable, Decodable, Hashable {
    let id: Int
    let name: String
}

nonisolated struct TMDBSeasonSummary: Sendable, Decodable, Hashable {
    let id: Int
    let name: String?
    let seasonNumber: Int?
    let episodeCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
    }
}

nonisolated struct TMDBCastMember: Sendable, Decodable, Hashable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, character
        case profilePath = "profile_path"
    }
}

nonisolated struct TMDBCreditsEnvelope: Sendable, Decodable {
    let cast: [TMDBCastMember]?
}

nonisolated struct TMDBSeason: Sendable, Decodable {
    let id: Int
    let name: String?
    let seasonNumber: Int?
    let episodes: [TMDBEpisode]?

    enum CodingKeys: String, CodingKey {
        case id, name, episodes
        case seasonNumber = "season_number"
    }
}

nonisolated struct TMDBEpisode: Sendable, Decodable, Hashable, Identifiable {
    let id: Int
    let name: String?
    let overview: String?
    let stillPath: String?
    let seasonNumber: Int?
    let episodeNumber: Int
    let airDate: String?
    let runtime: Int?

    /// Full TMDB still image URL, or nil if no still path. Mirrors the iOS
    /// `TMDBEpisode.stillUrl` convenience used by ShowDetailScreen cards.
    var stillUrl: String? { TVTMDBImage.url(stillPath, size: .original) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.overview = try c.decodeIfPresent(String.self, forKey: .overview)
        self.stillPath = try c.decodeIfPresent(String.self, forKey: .stillPath)
        self.seasonNumber = try c.decodeIfPresent(Int.self, forKey: .seasonNumber)
        self.episodeNumber = (try c.decodeIfPresent(Int.self, forKey: .episodeNumber)) ?? 0
        self.airDate = try c.decodeIfPresent(String.self, forKey: .airDate)
        self.runtime = try c.decodeIfPresent(Int.self, forKey: .runtime)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case stillPath = "still_path"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case airDate = "air_date"
    }
}

// MARK: - RemoteImage wrapper

/// iOS-named wrapper around `TVRemoteImage` that accepts the full iOS init
/// surface (`url:`, `urlString:`, optional `fallbackColors`). Shared views
/// pass `fallbackColors` for branded gradients — we use those as the
/// placeholder background on tvOS.
struct RemoteImage: View {
    private let url: URL?
    private let contentMode: ContentMode
    private let fallbackColors: [Color]

    init(url: URL?, contentMode: ContentMode = .fill, fallbackColors: [Color] = []) {
        self.url = url
        self.contentMode = contentMode
        self.fallbackColors = fallbackColors
    }

    init(urlString: String?, contentMode: ContentMode = .fill, fallbackColors: [Color] = []) {
        self.url = urlString.flatMap { URL(string: $0) }
        self.contentMode = contentMode
        self.fallbackColors = fallbackColors
    }

    var body: some View {
        ZStack {
            if !fallbackColors.isEmpty {
                LinearGradient(
                    colors: fallbackColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            TVRemoteImage(url: url, contentMode: contentMode)
        }
    }
}

// MARK: - Color extras

extension Color {
    static let textPrimary = Color.white
    static let newsGreen = Color(red: 0x00 / 255, green: 0x9E / 255, blue: 0x8A / 255)
}

// MARK: - Glass card modifier

extension View {
    /// Same glassy rounded-rectangle background the iOS app uses. Mirrors
    /// the iOS `.glassCard()` helper so shared views compile cleanly on
    /// tvOS without having to know which platform they're running on.
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}
