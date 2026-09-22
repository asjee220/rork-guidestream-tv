//
//  TVHomeRailsService.swift
//  GuideStreamTVTV
//
//  Supabase reads behind the Home rails the phone had and the TV did not
//  (GUI-102): the viewer's own New Episodes, Leaving Soon, and the live /
//  latest-upload state of followed creators for the hero. Same tables and
//  the same bounds the phone uses, so both screens show the same things.
//
//  Every call returns nil on failure, so a caller can keep whatever the
//  rail already shows instead of blanking it.
//

import Foundation
import Supabase

/// Row from `public.new_episodes`. The target's `NewEpisodeRow` is a
/// non-decodable stub for shared view signatures, so this is its own type.
nonisolated struct TVNewEpisodeRow: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let titleId: String
    let title: String?
    let titleName: String?
    let episodeTitle: String?
    let season: Int?
    let episode: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let platform: String?
    let posterUrl: String?
    let thumbnailUrl: String?
    let synopsis: String?
    let releasedAt: Date?

    /// Show name. `title` holds it on TMDB rows; creator rows put the
    /// upload's own title there and the channel name in `title_name`.
    var showName: String { titleName ?? title ?? "" }
    var seasonValue: Int? { season ?? seasonNumber }
    var episodeValue: Int? { episode ?? episodeNumber }
    var tmdbId: Int? { Int(titleId.trimmingCharacters(in: .whitespaces)) }

    enum CodingKeys: String, CodingKey {
        case id, title, season, episode, platform, synopsis
        case titleId = "title_id"
        case titleName = "title_name"
        case episodeTitle = "episode_title"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case posterUrl = "poster_url"
        case thumbnailUrl = "thumbnail_url"
        case releasedAt = "released_at"
    }
}

/// Row from `public.expiring_titles`, refreshed daily server-side.
nonisolated struct TVExpiringRow: Decodable, Identifiable, Hashable, Sendable {
    let tmdbId: Int
    let tmdbType: String?
    let title: String
    let posterUrl: String?
    let serviceName: String?
    let leavingDate: String?

    var id: Int { tmdbId }
    var isTV: Bool { tmdbType == "tv" }

    enum CodingKeys: String, CodingKey {
        case title
        case tmdbId = "tmdb_id"
        case tmdbType = "tmdb_type"
        case posterUrl = "poster_url"
        case serviceName = "service_name"
        case leavingDate = "leaving_date"
    }
}

@MainActor
enum TVHomeRailsService {

    /// Same window the phone reads new episodes over (StreamsViewModel.backlogDays).
    static let backlogDays: TimeInterval = 7

    private static var client: SupabaseClient { SupabaseManager.shared.client }

    /// New episodes and uploads for the given saved title ids, newest first.
    /// TMDB ids and creator ids are queried separately with their own cap,
    /// exactly as the phone does, so a busy creator cannot crowd out shows.
    static func fetchNewEpisodes(forTitleIds titleIds: [String]) async -> [TVNewEpisodeRow]? {
        guard !titleIds.isEmpty else { return [] }
        let cutoff = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-backlogDays * 86_400))
        let tmdbIds = titleIds.filter { Int($0.trimmingCharacters(in: .whitespaces)) != nil }
        let otherIds = titleIds.filter { Int($0.trimmingCharacters(in: .whitespaces)) == nil }
        do {
            var rows: [TVNewEpisodeRow] = []
            for ids in [tmdbIds, otherIds] where !ids.isEmpty {
                let batch: [TVNewEpisodeRow] = try await client
                    .from("new_episodes")
                    .select("id,title_id,title,title_name,episode_title,season,episode,season_number,episode_number,platform,poster_url,thumbnail_url,synopsis,released_at")
                    .in("title_id", values: ids)
                    .gte("released_at", value: cutoff)
                    .order("released_at", ascending: false)
                    .limit(20)
                    .execute()
                    .value
                rows.append(contentsOf: batch)
            }
            return rows.sorted { ($0.releasedAt ?? .distantPast) > ($1.releasedAt ?? .distantPast) }
        } catch {
            print("[TVHomeRails] fetchNewEpisodes failed: \(error)")
            return nil
        }
    }

    /// Titles leaving a service within `withinDays`, soonest first.
    static func fetchLeavingSoon(withinDays: Int = 20) async -> [TVExpiringRow]? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let today = formatter.string(from: Date())
        let horizon = formatter.string(from: Date().addingTimeInterval(Double(withinDays) * 86_400))
        do {
            let rows: [TVExpiringRow] = try await client
                .from("expiring_titles")
                .select("tmdb_id,tmdb_type,title,poster_url,service_name,leaving_date")
                .gte("leaving_date", value: today)
                .lte("leaving_date", value: horizon)
                .order("leaving_date", ascending: true)
                .limit(20)
                .execute()
                .value
            return rows
        } catch {
            print("[TVHomeRails] fetchLeavingSoon failed: \(error)")
            return nil
        }
    }

    /// Which of the given Twitch / Kick ids are live right now.
    static func fetchLive(titleIds: [String]) async -> [TVLiveStatus] {
        let ids = titleIds.filter { TVCreatorKind.from(titleId: $0)?.isLivestream == true }
        guard !ids.isEmpty else { return [] }
        do {
            let rows: [TVLiveStatus] = try await client
                .from("live_status")
                .select()
                .in("title_id", values: ids)
                .eq("is_live", value: true)
                .execute()
                .value
            return rows
        } catch {
            print("[TVHomeRails] fetchLive failed: \(error)")
            return []
        }
    }

    /// Whole days from today (UTC) to a `yyyy-MM-dd` date; nil if unparseable.
    static func daysUntil(_ dateString: String?) -> Int? {
        guard let dateString else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = formatter.date(from: dateString) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: date).day
    }
}
