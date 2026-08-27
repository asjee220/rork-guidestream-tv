//
//  TVTrailerStreamService.swift
//  GuideStreamTVTV
//
//  Turns the YouTube keys already sitting in `trailer_cache` into something
//  AVPlayer can actually open on Apple TV.
//
//  tvOS ships no WebKit — no WKWebView, no SFSafariViewController — so the
//  IFrame embed the phone app uses for Reels has no counterpart here.
//  YouTubeKit is a native Swift extractor (already a package dependency of
//  this project) that resolves a video id to a direct progressive stream
//  URL, which AVPlayer plays like any other MP4.
//
//  Two caveats worth keeping in the code where they cannot be forgotten:
//  extraction is outside YouTube's terms of service, and it breaks whenever
//  YouTube changes its player until the library ships a fix. Every failure
//  path here resolves to nil so the hero falls back to its still rather
//  than showing an error.
//

import Foundation
import Supabase
import YouTubeKit

private nonisolated struct TVTrailerCacheRow: Decodable, Sendable {
    let tmdbId: Int
    let mediaType: String
    let keys: [String]

    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case mediaType = "media_type"
        case keys
    }
}

@MainActor
@Observable
final class TVTrailerStreamService {
    static let shared = TVTrailerStreamService()

    private init() {}

    /// Resolved stream URLs keyed by YouTube video id. Extraction costs about
    /// a second per title, and googlevideo URLs stay valid for hours, so one
    /// resolve per key per launch is enough.
    private var resolved: [String: String] = [:]
    /// Keys that failed to resolve, so a dead video is not retried on every
    /// hero rebuild.
    private var failed: Set<String> = []

    private let selectedColumns = "tmdb_id,media_type,keys"

    /// Looks up cached YouTube keys for a hero pool and resolves the first
    /// playable stream for each. Returns a map keyed by canonicalTitleId
    /// ("tmdb:tv:123"); a missing key means that item renders as a still.
    func fetchTrailerStreams(for pool: [(tmdbId: Int, isTV: Bool)]) async -> [String: String] {
        let ids = Array(Set(pool.map { $0.tmdbId }))
        guard !ids.isEmpty else { return [:] }

        let rows: [TVTrailerCacheRow]
        do {
            rows = try await SupabaseManager.shared.client
                .from("trailer_cache")
                .select(selectedColumns)
                .in("tmdb_id", values: ids.map(String.init))
                .execute()
                .value
        } catch {
            return [:]
        }

        var isTVById: [Int: Bool] = [:]
        for entry in pool { isTVById[entry.tmdbId] = entry.isTV }

        // Match on media type as well as id — a film and a series can share a
        // TMDB id and their trailers are not interchangeable.
        var wanted: [(key: String, titleId: String)] = []
        for row in rows {
            guard let isTV = isTVById[row.tmdbId] else { continue }
            guard row.mediaType == (isTV ? "tv" : "movie") else { continue }
            guard let first = row.keys.first(where: { !failed.contains($0) }) else { continue }
            wanted.append((first, "tmdb:\(row.mediaType):\(row.tmdbId)"))
        }
        guard !wanted.isEmpty else { return [:] }

        var out: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for item in wanted {
                let cached = resolved[item.key]
                group.addTask {
                    if let cached { return (item.titleId, cached) }
                    return (item.titleId, await Self.streamURL(for: item.key))
                }
            }
            for await (titleId, url) in group {
                if let url { out[titleId] = url }
            }
        }

        // Record what resolved so a second hero build is instant.
        for item in wanted {
            if let url = out[item.titleId] {
                resolved[item.key] = url
            } else {
                failed.insert(item.key)
            }
        }

        return out
    }

    /// Highest-resolution progressive stream — one file carrying both video
    /// and audio, which AVPlayer can open directly. Adaptive DASH streams
    /// split the tracks and would need a manifest we cannot build here.
    private nonisolated static func streamURL(for videoID: String) async -> String? {
        do {
            let stream = try await YouTube(videoID: videoID).streams
                .filter { $0.includesVideoAndAudioTrack && $0.fileExtension == .mp4 }
                .highestResolutionStream()
            return stream?.url.absoluteString
        } catch {
            return nil
        }
    }
}
