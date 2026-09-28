//
//  TVHomeSnapshotStore.swift
//  GuideStreamTVTV
//
//  The tvOS twin of the phone's HomeSnapshotStore. Home writes what it last
//  rendered to the Caches directory; the next launch paints it before a
//  single request goes out, then the network load replaces it in place.
//  Apple TV evicts backgrounded apps readily, so nearly every open is a cold
//  start — without this the screen is a spinner until ~150 requests land.
//
//  Version-gated file name (bump `version` whenever the snapshot shape
//  changes), 24h max age, and a snapshot that fails to decode is simply
//  ignored. Never load-bearing: every rail still loads from the network.
//

import Foundation

nonisolated enum TVHomeSnapshotStore {
    /// Bump when TVHomeSnapshot's shape changes so old files are skipped.
    static let version = 1
    static let maxAge: TimeInterval = 24 * 60 * 60

    private struct Envelope<T: Codable & Sendable>: Codable, Sendable {
        let savedAt: Date
        let payload: T
    }

    private static var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("tv-home-snapshot-v\(version).json")
    }

    /// The last snapshot, if it is younger than `maxAge`.
    static func load<T: Codable>(_ type: T.Type) -> T? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let env = try? decoder.decode(Envelope<T>.self, from: data),
              Date().timeIntervalSince(env.savedAt) < maxAge else { return nil }
        return env.payload
    }

    /// Writes off the main actor; a failed write is silently dropped.
    static func save<T: Codable & Sendable>(_ payload: T) {
        guard let url = fileURL else { return }
        let env = Envelope(savedAt: Date(), payload: payload)
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(env) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
