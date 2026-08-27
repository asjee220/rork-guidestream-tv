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
    /// Keys not yet tried per title. A stream can resolve and still refuse to
    /// play — age-gated and region-locked videos hand back a URL that then
    /// 403s — so the carousel asks for the next one instead of giving up.
    private var candidateKeys: [String: [String]] = [:]

    private let selectedColumns = "tmdb_id,media_type,keys"

    /// Looks up cached YouTube keys for a hero pool and resolves the first
    /// playable stream for each. Returns a map keyed by canonicalTitleId
    /// ("tmdb:tv:123"); a missing key means that item renders as a still.
    func fetchTrailerStreams(for pool: [(tmdbId: Int, isTV: Bool)]) async -> [String: String] {
        let ids = Array(Set(pool.map { $0.tmdbId }))
        guard !ids.isEmpty else { return [:] }

        var rows: [TVTrailerCacheRow] = []
        do {
            rows = try await SupabaseManager.shared.client
                .from("trailer_cache")
                .select(selectedColumns)
                .in("tmdb_id", values: ids.map(String.init))
                .execute()
                .value
        } catch {
            // A cache miss is not fatal — TMDB is asked directly below.
            rows = []
        }

        var isTVById: [Int: Bool] = [:]
        for entry in pool { isTVById[entry.tmdbId] = entry.isTV }

        // Match on media type as well as id — a film and a series can share a
        // TMDB id and their trailers are not interchangeable.
        var keyByTmdbId: [Int: String] = [:]
        var allKeysByTmdbId: [Int: [String]] = [:]
        for row in rows {
            guard let isTV = isTVById[row.tmdbId] else { continue }
            guard row.mediaType == (isTV ? "tv" : "movie") else { continue }
            let usable = row.keys.filter { !failed.contains($0) }
            guard let first = usable.first else { continue }
            keyByTmdbId[row.tmdbId] = first
            allKeysByTmdbId[row.tmdbId] = usable
        }

        // trailer_cache is filled by the Reels ingest, so it covers whatever
        // Reels has surfaced — not the trending-and-on-the-air pool this hero
        // draws from. Ask TMDB directly for anything the cache does not carry,
        // which is the same /videos lookup the title sheet already makes.
        let uncached = pool.filter { keyByTmdbId[$0.tmdbId] == nil }
        if !uncached.isEmpty {
            await withTaskGroup(of: (Int, String?).self) { group in
                for entry in uncached {
                    group.addTask {
                        let key = try? await TVTMDBService.shared.getTrailerKey(
                            tmdbId: entry.tmdbId,
                            isTV: entry.isTV
                        )
                        return (entry.tmdbId, key ?? nil)
                    }
                }
                for await (tmdbId, key) in group {
                    if let key, !failed.contains(key) {
                        keyByTmdbId[tmdbId] = key
                        allKeysByTmdbId[tmdbId] = [key]
                    }
                }
            }
        }

        var wanted: [(key: String, titleId: String)] = []
        for entry in pool {
            guard let key = keyByTmdbId[entry.tmdbId] else { continue }
            let kind = entry.isTV ? "tv" : "movie"
            let titleId = "tmdb:\(kind):\(entry.tmdbId)"
            wanted.append((key, titleId))
            // Everything after the one being tried now.
            candidateKeys[titleId] = Array((allKeysByTmdbId[entry.tmdbId] ?? [key]).dropFirst())
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

        #if DEBUG
        await logDiagnostics(pool: pool, keys: keyByTmdbId, resolvedURLs: out)
        #endif

        return out
    }

    /// Next playable stream for a title whose current one refused to play.
    /// Returns nil once the alternatives are exhausted, and the hero keeps
    /// its still.
    func nextStreamURL(for titleId: String) async -> String? {
        while var keys = candidateKeys[titleId], !keys.isEmpty {
            let key = keys.removeFirst()
            candidateKeys[titleId] = keys
            if let url = await Self.streamURL(for: key) {
                resolved[key] = url
                return url
            }
            failed.insert(key)
        }
        return nil
    }

    #if DEBUG
    /// Writes one row per hero item to debug_logs so the resolution path can
    /// be inspected without a console. Debug builds only.
    private func logDiagnostics(
        pool: [(tmdbId: Int, isTV: Bool)],
        keys: [Int: String],
        resolvedURLs: [String: String]
    ) async {
        for entry in pool {
            let kind = entry.isTV ? "tv" : "movie"
            let titleId = "tmdb:\(kind):\(entry.tmdbId)"
            let key = keys[entry.tmdbId]
            let url = resolvedURLs[titleId]
            try? await SupabaseManager.shared.client
                .from("debug_logs")
                .insert([
                    "event": .string("tv_hero_video"),
                    "platform": .string("tvos"),
                    "title": .string(titleId),
                    "target_name": .string(key ?? "NO_KEY"),
                    "content_url": .string(url.map { String($0.prefix(120)) } ?? "NO_STREAM"),
                    "matched": .bool(url != nil)
                ] as [String: AnyJSON])
                .execute()
        }
    }
    #endif

    /// Highest-resolution progressive stream — one file carrying both video
    /// and audio, which AVPlayer can open directly. Adaptive DASH streams
    /// split the tracks and would need a manifest we cannot build here.
    private nonisolated static func streamURL(for videoID: String) async -> String? {
        do {
            let streams = try await YouTube(videoID: videoID).streams
            // isNativelyPlayable is codec-aware, where an .mp4 extension is
            // not: three of five heroes were handed mp4 containers Apple TV
            // could not decode and the item went straight to .failed.
            let playable = streams.filter { $0.isNativelyPlayable && $0.includesVideoAndAudioTrack }
            // Cap at 720p. Progressive YouTube tops out there anyway, and a
            // muted hero sitting behind a scrim gains nothing from more.
            let capped = playable.filter { ($0.videoResolution ?? 0) <= 720 }
            let chosen = (capped.isEmpty ? playable : capped)
                .max { ($0.videoResolution ?? 0) < ($1.videoResolution ?? 0) }
            return chosen?.url.absoluteString
        } catch {
            return nil
        }
    }
}
