//
//  TVStreamsViewModel.swift
//  GuideStreamTVTV
//
//  Watch list store for the Apple TV app. Mirrors the phone app's
//  `StreamsViewModel`:
//
//   1. Local cache in UserDefaults so the watch list renders instantly
//      on cold launch and survives offline restarts.
//   2. Supabase `user_streams` is the durable source of truth — every
//      change is written through with the same ownership rules
//      (signed-in users own rows via `user_id`, guests via `device_id`).
//   3. Failures never undo the local optimistic update; we just log
//      and keep the device-local copy.
//

import Foundation
import Supabase

@MainActor
@Observable
final class TVStreamsViewModel {
    static let shared = TVStreamsViewModel()

    var userStreams: [TVUserStream] = []
    var isLoading: Bool = false
    var lastError: String?

    private let localCacheKey = "gs.tv.watchList.localCache.v1"
    private static let guestUserId = "guest"

    private var currentUserId: UUID? {
        TVAuthViewModel.shared.currentUser?.id
    }

    private init() {
        self.userStreams = loadLocalCache()
    }

    /// Pulls the canonical list. Falls back to the local cache on any
    /// network/RLS failure so the watch list never appears to vanish.
    func fetchUserStreams() async {
        isLoading = true
        defer { isLoading = false }
        let deviceId = TVDeviceIdentity.shared.deviceId
        do {
            var query = TVSupabaseManager.shared.client
                .from("user_streams")
                .select()
            if let uid = currentUserId?.uuidString {
                query = query.or("user_id.eq.\(uid),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            let rows: [TVUserStream] = try await query
                .order("added_at", ascending: false)
                .execute()
                .value
            let merged = mergeRemoteWithLocal(remote: rows)
            self.userStreams = merged
            saveLocalCache(merged)
        } catch {
            self.lastError = error.localizedDescription
            print("[TVStreams] fetchUserStreams failed: \(error.localizedDescription)")
            self.userStreams = loadLocalCache()
        }
    }

    /// Returns true when the given titleId is currently in the watch list.
    func contains(titleId: String) -> Bool {
        userStreams.contains { $0.titleId == titleId }
    }

    /// Toggle a title in/out of the watch list. Used by the focus
    /// poster cards on Home — one click is the whole interaction.
    func toggle(
        titleId: String,
        title: String?,
        posterUrl: String?,
        platform: String?
    ) async {
        if contains(titleId: titleId) {
            await remove(titleId: titleId)
        } else {
            await add(titleId: titleId, title: title, posterUrl: posterUrl, platform: platform)
        }
    }

    func add(titleId: String, title: String?, posterUrl: String?, platform: String?) async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if !userStreams.contains(where: { $0.titleId == trimmed }) {
            let optimistic = TVUserStream(
                id: UUID().uuidString,
                userId: currentUserId?.uuidString ?? Self.guestUserId,
                titleId: trimmed,
                title: title,
                posterUrl: posterUrl,
                platform: platform,
                addedAt: Date()
            )
            self.userStreams.insert(optimistic, at: 0)
            saveLocalCache(self.userStreams)
        }

        let didInsert = await insertUserStream(
            userId: currentUserId?.uuidString,
            deviceId: TVDeviceIdentity.shared.deviceId,
            titleId: trimmed,
            title: title,
            posterUrl: posterUrl,
            platform: platform
        )
        if didInsert {
            await fetchUserStreams()
        }
    }

    func remove(titleId: String) async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        self.userStreams.removeAll { $0.titleId == trimmed }
        saveLocalCache(self.userStreams)

        let deviceId = TVDeviceIdentity.shared.deviceId
        do {
            var query = TVSupabaseManager.shared.client
                .from("user_streams")
                .delete()
                .eq("title_id", value: trimmed)
            if let uid = currentUserId?.uuidString {
                query = query.or("user_id.eq.\(uid),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            try await query.execute()
        } catch {
            self.lastError = error.localizedDescription
            print("[TVStreams] remove failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func insertUserStream(
        userId: String?,
        deviceId: String,
        titleId: String,
        title: String?,
        posterUrl: String?,
        platform: String?
    ) async -> Bool {
        let safeTitle = title ?? titleId
        var payload: [String: AnyJSON] = [
            "device_id": .string(deviceId),
            "title_id": .string(titleId),
            "title_name": .string(safeTitle)
        ]
        if let userId { payload["user_id"] = .string(userId) }
        if let title { payload["title"] = .string(title) }
        if let posterUrl { payload["poster_url"] = .string(posterUrl) }
        if let platform { payload["platform"] = .string(platform) }

        for attempt in 0..<5 {
            do {
                try await TVSupabaseManager.shared.client
                    .from("user_streams")
                    .insert(payload)
                    .execute()
                self.lastError = nil
                return true
            } catch {
                let message = error.localizedDescription
                let lowered = message.lowercased()
                if lowered.contains("duplicate") || lowered.contains("23505") {
                    return true
                }
                if attempt < 4, let dropped = Self.dropMissingColumn(from: payload, error: message) {
                    payload = dropped
                    continue
                }
                if attempt < 4,
                   let filled = Self.fillNotNullViolation(in: payload, error: message, fallback: safeTitle) {
                    payload = filled
                    continue
                }
                self.lastError = message
                print("[TVStreams] add failed: \(message)")
                return false
            }
        }
        return false
    }

    // MARK: - Local cache helpers

    private func loadLocalCache() -> [TVUserStream] {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([TVUserStream].self, from: data)
        } catch {
            return []
        }
    }

    private func saveLocalCache(_ streams: [TVUserStream]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(streams)
            UserDefaults.standard.set(data, forKey: localCacheKey)
        } catch {
            // best effort
        }
    }

    private func mergeRemoteWithLocal(remote: [TVUserStream]) -> [TVUserStream] {
        let remoteTitleIds = Set(remote.map { $0.titleId })
        let pendingLocal = loadLocalCache().filter { !remoteTitleIds.contains($0.titleId) }
        return remote + pendingLocal
    }

    private static func dropMissingColumn(
        from payload: [String: AnyJSON],
        error: String
    ) -> [String: AnyJSON]? {
        let lowered = error.lowercased()
        guard lowered.contains("could not find") && lowered.contains("column") else { return nil }
        var trimmed = payload
        var didDrop = false
        for key in Array(payload.keys) where key != "title_id" {
            if lowered.contains("'\(key.lowercased())'") {
                trimmed.removeValue(forKey: key)
                didDrop = true
            }
        }
        return didDrop ? trimmed : nil
    }

    private static func fillNotNullViolation(
        in payload: [String: AnyJSON],
        error: String,
        fallback: String
    ) -> [String: AnyJSON]? {
        let lowered = error.lowercased()
        guard lowered.contains("23502") || lowered.contains("not-null constraint") else { return nil }
        guard let range = error.range(of: "column \"", options: .caseInsensitive) else { return nil }
        let after = error[range.upperBound...]
        guard let end = after.firstIndex(of: "\"") else { return nil }
        let column = String(after[..<end])
        guard !column.isEmpty, payload[column] == nil else { return nil }
        var filled = payload
        filled[column] = .string(fallback)
        return filled
    }
}
