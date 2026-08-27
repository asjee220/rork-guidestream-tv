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
    /// Alternative stream URLs already resolved for the title's current key,
    /// best first. Tried before moving on to another key — a 1080p rendition
    /// that 403s is no reason to give up on the trailer itself.
    private var pendingURLs: [String: [String]] = [:]
    /// Resolution of the stream picked for each key, for the diagnostics.
    private var resolvedResolution: [String: Int] = [:]

    private let selectedColumns = "tmdb_id,media_type,keys"

    /// Stream extractions allowed to run at once. See fetchTrailerStreams.
    private static let maxConcurrentExtractions = 2

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
            await withTaskGroup(of: (Int, [String]).self) { group in
                for entry in uncached {
                    group.addTask {
                        let keys = await TVTMDBService.shared.getTrailerKeys(
                            tmdbId: entry.tmdbId,
                            isTV: entry.isTV
                        )
                        return (entry.tmdbId, keys)
                    }
                }
                for await (tmdbId, keys) in group {
                    // Every ranked key, not just the best one. A single dead
                    // key used to mean that title showed no video at all.
                    let usable = keys.filter { !failed.contains($0) }
                    guard let first = usable.first else { continue }
                    keyByTmdbId[tmdbId] = first
                    allKeysByTmdbId[tmdbId] = usable
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

        // Resolve two at a time, never the whole pool at once. Extraction
        // runs YouTube's descrambler through JavaScriptCore, and six of those
        // in flight together blew the 2GB per-app limit on a real Apple TV —
        // the app was killed in JSC::BlockDirectory::tryAllocateBlock, which
        // is also why some titles came up with no video at all.
        var out: [String: String] = [:]
        var chosenResolution: [String: Int] = [:]
        for chunk in stride(from: 0, to: wanted.count, by: Self.maxConcurrentExtractions).map({
            Array(wanted[$0..<min($0 + Self.maxConcurrentExtractions, wanted.count)])
        }) {
            await withTaskGroup(of: (String, [String], Int).self) { group in
                for item in chunk {
                    let cached = resolved[item.key]
                    let cachedRes = resolvedResolution[item.key]
                    group.addTask {
                        if let cached { return (item.titleId, [cached], cachedRes ?? 0) }
                        let result = await Self.streamCandidatesWithResolution(for: item.key)
                        return (item.titleId, result.urls, result.resolution)
                    }
                }
                for await (titleId, urls, resolution) in group {
                    guard let best = urls.first else { continue }
                    out[titleId] = best
                    pendingURLs[titleId] = Array(urls.dropFirst())
                    chosenResolution[titleId] = resolution
                }
            }
        }

        // Record what resolved so a second hero build is instant.
        for item in wanted {
            if let url = out[item.titleId] {
                resolved[item.key] = url
                resolvedResolution[item.key] = chosenResolution[item.titleId] ?? 0
            } else {
                failed.insert(item.key)
            }
        }

        #if DEBUG
        await logDiagnostics(
            pool: pool,
            keys: keyByTmdbId,
            resolvedURLs: out,
            resolutions: chosenResolution
        )
        #endif

        return out
    }

    /// Next playable stream for a title whose current one refused to play.
    /// Returns nil once the alternatives are exhausted, and the hero keeps
    /// its still.
    func nextStreamURL(for titleId: String) async -> String? {
        // Another rendition of the same trailer first — cheapest and most
        // likely to work, since the key itself already resolved.
        if var urls = pendingURLs[titleId], !urls.isEmpty {
            let url = urls.removeFirst()
            pendingURLs[titleId] = urls
            return url
        }
        while var keys = candidateKeys[titleId], !keys.isEmpty {
            let key = keys.removeFirst()
            candidateKeys[titleId] = keys
            let urls = await Self.streamCandidates(for: key)
            if let best = urls.first {
                resolved[key] = best
                pendingURLs[titleId] = Array(urls.dropFirst())
                return best
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
        resolvedURLs: [String: String],
        resolutions: [String: Int]
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
                    "device_kind": .string({
                        let res = resolutions[titleId] ?? 0
                        return res == 0 ? "none" : "\(res)p"
                    }()),
                    "matched": .bool((resolutions[titleId] ?? 0) >= 1080)
                ] as [String: AnyJSON])
                .execute()
        }
    }
    #endif

    /// Playable streams for one video, best first.
    ///
    /// The hero plays muted, so an audio track is dead weight — and that is
    /// what was capping quality. `includesVideoAndAudioTrack` is an alias for
    /// "progressive", and progressive YouTube tops out at 720p; the 1080p and
    /// better renditions are all adaptive, video-only. Dropping the audio
    /// requirement puts them back on the table, and AVPlayer opens a
    /// video-only MP4 the same as any other.
    ///
    /// `isNativelyPlayable` is codec-aware where an `.mp4` extension is not:
    /// three of five heroes were once handed mp4 containers Apple TV could
    /// not decode, and went straight to `.failed`.
    ///
    /// Ranked highest resolution first, capped at 1080 — a muted hero behind
    /// a scrim gains nothing above that and 4K costs bandwidth for nothing.
    /// At equal resolution a progressive stream wins, being the better-trodden
    /// path. Returns several so a URL that resolves but then refuses to play
    /// can be stepped past without abandoning the title.
    private nonisolated static func streamCandidates(for videoID: String) async -> [String] {
        await streamCandidatesWithResolution(for: videoID).urls
    }

    /// As above, plus the resolution actually chosen — 0 when nothing
    /// resolved. Recorded so the titles that cannot reach 1080 from YouTube
    /// are a list rather than a guess: those are the ones worth a hosted
    /// featurette in `title_featurettes`.
    private nonisolated static func streamCandidatesWithResolution(
        for videoID: String
    ) async -> (urls: [String], resolution: Int) {
        do {
            let streams = try await YouTube(videoID: videoID).streams
            let playable = streams.filter { $0.isNativelyPlayable && $0.includesVideoTrack }
            let capped = playable.filter { ($0.videoResolution ?? 0) <= 1080 }
            let pool = capped.isEmpty ? playable : capped
            let ranked = pool.sorted { lhs, rhs in
                let lr = lhs.videoResolution ?? 0
                let rr = rhs.videoResolution ?? 0
                if lr != rr { return lr > rr }
                return lhs.includesVideoAndAudioTrack && !rhs.includesVideoAndAudioTrack
            }
            return (ranked.prefix(4).map { $0.url.absoluteString },
                    ranked.first?.videoResolution ?? 0)
        } catch {
            return ([], 0)
        }
    }
}
