//
//  SocialViewModel.swift
//  GuideStreamTV
//
//  Likes + comments per title, with the same local-first / Supabase
//  write-through model as `StreamsViewModel`:
//
//  1. Local in-memory state updates immediately so the UI reflects every
//     tap on the next frame, regardless of network/Supabase state.
//  2. A small UserDefaults cache persists the user's like state + last
//     known counts so cold launches render instantly.
//  3. When a Supabase row exists we push to `title_likes` /
//     `title_comments`; failures are logged but never undo local state.
//
//  Ownership matches the watchlist:
//  - signed-in users own rows via `user_id`
//  - guests / unauthenticated devices own rows via `device_id`
//
//  Toggling a like is idempotent thanks to the partial unique indexes
//  defined in `SupabaseSetupSQL`. Comments are append-only.
//

import Foundation
import Supabase

/// Single comment row, decoded straight from `title_comments`.
nonisolated struct TitleComment: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let titleId: String
    let userId: String?
    let deviceId: String?
    let body: String
    let displayName: String?
    let initials: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case titleId = "title_id"
        case userId = "user_id"
        case deviceId = "device_id"
        case body
        case displayName = "display_name"
        case initials
        case createdAt = "created_at"
    }
}

@MainActor
@Observable
final class SocialViewModel {
    static let shared = SocialViewModel()

    /// Total like count per title_id. Hydrated from the local cache on init
    /// so the actions row shows the last known number on cold launch.
    private(set) var likeCounts: [String: Int] = [:]
    /// Title_ids the current device/user has liked.
    private(set) var likedByMe: Set<String> = []
    /// Title_ids the current device/user has marked watched (series-level).
    private(set) var watchedByMe: Set<String> = []
    /// Total comment count per title_id.
    private(set) var commentCounts: [String: Int] = [:]
    /// Most recent comment thread per title_id (latest first).
    private(set) var commentsByTitle: [String: [TitleComment]] = [:]

    /// Titles whose comment thread is currently being fetched.
    private(set) var loadingComments: Set<String> = []
    /// Titles whose like/comment counts are currently being refreshed.
    private(set) var loadingCounts: Set<String> = []
    /// Titles whose like state is currently being toggled (server in-flight).
    private(set) var togglingLikes: Set<String> = []
    /// Titles whose watched state is currently being toggled (server in-flight).
    private(set) var togglingWatched: Set<String> = []
    /// Titles whose comment post is currently being submitted.
    private(set) var postingComment: Set<String> = []

    var lastError: String?

    private let localCacheKey = "gs.social.cache.v1"

    private var currentUserId: UUID? {
        AuthViewModel.shared.currentUser?.id
    }

    private init() {
        hydrateFromCache()
    }

    // MARK: - Read accessors

    func likes(_ titleId: String) -> Int { likeCounts[titleId] ?? 0 }
    func isLiked(_ titleId: String) -> Bool { likedByMe.contains(titleId) }
    func isWatched(_ titleId: String) -> Bool { watchedByMe.contains(titleId) }
    func commentTotal(_ titleId: String) -> Int { commentCounts[titleId] ?? 0 }
    func thread(_ titleId: String) -> [TitleComment] { commentsByTitle[titleId] ?? [] }

    // MARK: - Refresh

    /// Pulls the latest like count, my-like state, and comment count for a
    /// title in parallel. Safe to call multiple times — concurrent calls
    /// coalesce via `loadingCounts`.
    func refreshCounts(titleId: String) async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !loadingCounts.contains(trimmed) else { return }
        loadingCounts.insert(trimmed)
        defer { loadingCounts.remove(trimmed) }

        async let likeTotal: Int = fetchLikeCount(titleId: trimmed)
        async let mineLiked: Bool = fetchHasLiked(titleId: trimmed)
        async let mineWatched: Bool = fetchHasWatched(titleId: trimmed)
        async let commentTotal: Int = fetchCommentCount(titleId: trimmed)

        let (lt, ml, mw, ct) = await (likeTotal, mineLiked, mineWatched, commentTotal)
        likeCounts[trimmed] = lt
        commentCounts[trimmed] = ct
        if ml {
            likedByMe.insert(trimmed)
        } else {
            // Only un-flag if the server has no row — otherwise an in-flight
            // optimistic local like would get reverted by this refresh.
            if !togglingLikes.contains(trimmed) {
                likedByMe.remove(trimmed)
            }
        }
        if mw {
            watchedByMe.insert(trimmed)
        } else {
            // Only un-flag if the server has no row — otherwise an in-flight
            // optimistic local watched would get reverted by this refresh.
            if !togglingWatched.contains(trimmed) {
                watchedByMe.remove(trimmed)
            }
        }
        saveCache()
    }

    private func fetchLikeCount(titleId: String) async -> Int {
        do {
            let response = try await SupabaseManager.shared.client
                .from("title_likes")
                .select("*", head: true, count: .exact)
                .eq("title_id", value: titleId)
                .execute()
            return response.count ?? 0
        } catch {
            print("[Social] like count fetch failed: \(error.localizedDescription)")
            return likeCounts[titleId] ?? 0
        }
    }

    private func fetchHasLiked(titleId: String) async -> Bool {
        let deviceId = DeviceIdentity.shared.deviceId
        do {
            var query = SupabaseManager.shared.client
                .from("title_likes")
                .select("id", head: true, count: .exact)
                .eq("title_id", value: titleId)
            if let uid = currentUserId?.uuidString {
                query = query.or("user_id.eq.\(uid),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            let response = try await query.execute()
            return (response.count ?? 0) > 0
        } catch {
            print("[Social] hasLiked fetch failed: \(error.localizedDescription)")
            return likedByMe.contains(titleId)
        }
    }

    /// Loads every `title_watched` row owned by the current user/device in a
    /// single query and replaces `watchedByMe` with that set. Display-only:
    /// used by the Watch List to show the eye badge on saved titles that are
    /// already marked watched. Never writes to `title_watched`.
    func loadAllWatched() async {
        let deviceId = DeviceIdentity.shared.deviceId
        do {
            var query = SupabaseManager.shared.client
                .from("title_watched")
                .select("title_id")
            if let uid = currentUserId?.uuidString {
                query = query.or("user_id.eq.\(uid),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            struct WatchedIdRow: Decodable {
                let titleId: String
                enum CodingKeys: String, CodingKey { case titleId = "title_id" }
            }
            let rows: [WatchedIdRow] = try await query.execute().value
            watchedByMe = Set(rows.map { $0.titleId })
            saveCache()
        } catch {
            print("[Social] loadAllWatched failed: \(error.localizedDescription)")
        }
    }

    private func fetchHasWatched(titleId: String) async -> Bool {
        let deviceId = DeviceIdentity.shared.deviceId
        do {
            var query = SupabaseManager.shared.client
                .from("title_watched")
                .select("id", head: true, count: .exact)
                .eq("title_id", value: titleId)
            if let uid = currentUserId?.uuidString {
                query = query.or("user_id.eq.\(uid),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            let response = try await query.execute()
            return (response.count ?? 0) > 0
        } catch {
            print("[Social] hasWatched fetch failed: \(error.localizedDescription)")
            return watchedByMe.contains(titleId)
        }
    }

    private func fetchCommentCount(titleId: String) async -> Int {
        do {
            let response = try await SupabaseManager.shared.client
                .from("title_comments")
                .select("*", head: true, count: .exact)
                .eq("title_id", value: titleId)
                .execute()
            return response.count ?? 0
        } catch {
            print("[Social] comment count fetch failed: \(error.localizedDescription)")
            return commentCounts[titleId] ?? 0
        }
    }

    // MARK: - Likes

    /// Toggle the user's like on `titleId`. Local state flips immediately so
    /// the UI reacts on the next frame; the Supabase write happens in the
    /// background and is best-effort.
    ///
    /// `mediaType` ("tv" or "movie") and `tmdbId` describe the title so each
    /// `title_likes` row records what kind of title it is and its TMDB id.
    /// They are optional because some likeable entries (e.g. sports games)
    /// have no TMDB identity; those rows simply omit the columns.
    func toggleLike(titleId: String, mediaType: String? = nil, tmdbId: Int? = nil) async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        togglingLikes.insert(trimmed)
        defer { togglingLikes.remove(trimmed) }

        let wasLiked = likedByMe.contains(trimmed)
        // Optimistic local flip.
        if wasLiked {
            likedByMe.remove(trimmed)
            likeCounts[trimmed] = max(0, (likeCounts[trimmed] ?? 1) - 1)
        } else {
            likedByMe.insert(trimmed)
            likeCounts[trimmed] = (likeCounts[trimmed] ?? 0) + 1
        }
        saveCache()

        WatchIntentLogger.shared.log(
            eventType: .trailerLiked,
            titleId: trimmed,
            metadata: ["liked": !wasLiked, "source": "detail_sheet"]
        )

        var watchlistMeta: [String: Any] = ["source": "detail_sheet"]
        if let mediaType { watchlistMeta["media_type"] = mediaType }
        WatchIntentLogger.shared.log(
            eventType: wasLiked ? .watchlistRemoved : .watchlistAdded,
            titleId: trimmed,
            metadata: watchlistMeta
        )

        let deviceId = DeviceIdentity.shared.deviceId
        let userId = currentUserId?.uuidString
        if wasLiked {
            await removeLike(titleId: trimmed, userId: userId, deviceId: deviceId)
        } else {
            await insertLike(titleId: trimmed, userId: userId, deviceId: deviceId, mediaType: mediaType, tmdbId: tmdbId)
        }
        // Refresh the canonical count once Supabase has settled.
        let canonical = await fetchLikeCount(titleId: trimmed)
        likeCounts[trimmed] = canonical
        saveCache()
    }

    @discardableResult
    private func insertLike(titleId: String, userId: String?, deviceId: String, mediaType: String?, tmdbId: Int?) async -> Bool {
        var payload: [String: AnyJSON] = [
            "title_id": .string(titleId),
            "device_id": .string(deviceId)
        ]
        if let userId { payload["user_id"] = .string(userId) }
        if let mediaType { payload["media_type"] = .string(mediaType) }
        if let tmdbId { payload["tmdb_id"] = .integer(tmdbId) }
        do {
            try await SupabaseManager.shared.client
                .from("title_likes")
                .insert(payload)
                .execute()
            return true
        } catch {
            let message = error.localizedDescription.lowercased()
            // Duplicate is fine — partial unique index hit means the like
            // already exists for this owner. Silently bring its media_type /
            // tmdb_id up to date instead of surfacing an error.
            if message.contains("duplicate") || message.contains("23505") {
                await updateLikeMetadata(titleId: titleId, userId: userId, deviceId: deviceId, mediaType: mediaType, tmdbId: tmdbId)
                return true
            }
            if message.contains("42501") || message.contains("row-level security") {
                self.lastError = "Supabase blocked the like. Open Profile → Diagnostics and run the schema setup SQL."
            } else {
                self.lastError = error.localizedDescription
            }
            print("[Social] like insert failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Silent best-effort update of an existing like row's `media_type` /
    /// `tmdb_id` for this owner. Used when an insert hits the partial unique
    /// index (the like already existed). Never surfaces an error.
    private func updateLikeMetadata(titleId: String, userId: String?, deviceId: String, mediaType: String?, tmdbId: Int?) async {
        var values: [String: AnyJSON] = [:]
        if let mediaType { values["media_type"] = .string(mediaType) }
        if let tmdbId { values["tmdb_id"] = .integer(tmdbId) }
        guard !values.isEmpty else { return }
        do {
            var query = try SupabaseManager.shared.client
                .from("title_likes")
                .update(values)
                .eq("title_id", value: titleId)
            if let userId {
                query = query.or("user_id.eq.\(userId),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            try await query.execute()
        } catch {
            print("[Social] like metadata update failed: \(error.localizedDescription)")
        }
    }

    private func removeLike(titleId: String, userId: String?, deviceId: String) async {
        do {
            var query = SupabaseManager.shared.client
                .from("title_likes")
                .delete()
                .eq("title_id", value: titleId)
            if let userId {
                query = query.or("user_id.eq.\(userId),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            try await query.execute()
        } catch {
            self.lastError = error.localizedDescription
            print("[Social] like delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Watched (series-level)

    /// Toggle the user's series-level "watched" flag on `titleId`. Structural
    /// mirror of `toggleLike`: local state flips immediately, then a
    /// best-effort write-through to `title_watched` happens in the background.
    /// One tap marks the whole series — never per-episode.
    func toggleWatched(titleId: String, titleName: String? = nil, mediaType: String? = nil, tmdbId: Int? = nil) async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        togglingWatched.insert(trimmed)
        defer { togglingWatched.remove(trimmed) }

        let wasWatched = watchedByMe.contains(trimmed)
        // Optimistic local flip.
        if wasWatched {
            watchedByMe.remove(trimmed)
        } else {
            watchedByMe.insert(trimmed)
        }
        saveCache()

        var meta: [String: Any] = ["watched": !wasWatched, "source": "detail_sheet"]
        if let mediaType { meta["media_type"] = mediaType }
        WatchIntentLogger.shared.log(
            eventType: .watchedToggled,
            titleId: trimmed,
            metadata: meta
        )

        let deviceId = DeviceIdentity.shared.deviceId
        let userId = currentUserId?.uuidString
        if wasWatched {
            await removeWatched(titleId: trimmed, userId: userId, deviceId: deviceId)
        } else {
            await insertWatched(titleId: trimmed, userId: userId, deviceId: deviceId, titleName: titleName, mediaType: mediaType, tmdbId: tmdbId)
        }
    }

    @discardableResult
    private func insertWatched(titleId: String, userId: String?, deviceId: String, titleName: String?, mediaType: String?, tmdbId: Int?) async -> Bool {
        var payload: [String: AnyJSON] = [
            "title_id": .string(titleId),
            "device_id": .string(deviceId)
        ]
        if let userId { payload["user_id"] = .string(userId) }
        if let titleName { payload["title_name"] = .string(titleName) }
        if let mediaType { payload["media_type"] = .string(mediaType) }
        if let tmdbId { payload["tmdb_id"] = .integer(tmdbId) }
        do {
            try await SupabaseManager.shared.client
                .from("title_watched")
                .insert(payload)
                .execute()
            return true
        } catch {
            let message = error.localizedDescription.lowercased()
            // Duplicate is fine — partial unique index hit means the watched
            // row already exists for this owner. Treat as success.
            if message.contains("duplicate") || message.contains("23505") {
                return true
            }
            if message.contains("42501") || message.contains("row-level security") {
                self.lastError = "Supabase blocked the watched mark. Open Profile → Diagnostics and run the schema setup SQL."
            } else {
                self.lastError = error.localizedDescription
            }
            print("[Social] watched insert failed: \(error.localizedDescription)")
            return false
        }
    }

    private func removeWatched(titleId: String, userId: String?, deviceId: String) async {
        do {
            var query = SupabaseManager.shared.client
                .from("title_watched")
                .delete()
                .eq("title_id", value: titleId)
            if let userId {
                query = query.or("user_id.eq.\(userId),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            try await query.execute()
        } catch {
            self.lastError = error.localizedDescription
            print("[Social] watched delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Comments

    /// Load the latest comment thread for `titleId` (up to 200). Also
    /// refreshes the comment count side effect-free.
    func loadComments(titleId: String, limit: Int = 200) async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        loadingComments.insert(trimmed)
        defer { loadingComments.remove(trimmed) }
        do {
            let rows: [TitleComment] = try await SupabaseManager.shared.client
                .from("title_comments")
                .select()
                .eq("title_id", value: trimmed)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            commentsByTitle[trimmed] = rows
            commentCounts[trimmed] = rows.count
            saveCache()
        } catch {
            self.lastError = error.localizedDescription
            print("[Social] loadComments failed: \(error.localizedDescription)")
        }
    }

    /// Append a new comment to `titleId`. Returns `true` on success. The
    /// thread + count update immediately so the UI feels responsive even if
    /// the network write is slow.
    @discardableResult
    func postComment(titleId: String, body: String) async -> Bool {
        let trimmedId = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedBody.isEmpty else { return false }
        postingComment.insert(trimmedId)
        defer { postingComment.remove(trimmedId) }

        let auth = AuthViewModel.shared
        let deviceId = DeviceIdentity.shared.deviceId
        let userId = auth.currentUser?.id.uuidString
        let displayName = auth.displayName
            ?? composedName(first: auth.firstName, last: auth.lastName)
            ?? auth.currentUser?.email.flatMap { handle(from: $0) }
            ?? "You"
        let initials = Self.initials(firstName: auth.firstName, lastName: auth.lastName, displayName: displayName)

        // Optimistic insert — show the comment immediately at the top of
        // the thread with a placeholder id.
        let optimistic = TitleComment(
            id: "local-\(UUID().uuidString)",
            titleId: trimmedId,
            userId: userId,
            deviceId: deviceId,
            body: trimmedBody,
            displayName: displayName,
            initials: initials,
            createdAt: Date()
        )
        var current = commentsByTitle[trimmedId] ?? []
        current.insert(optimistic, at: 0)
        commentsByTitle[trimmedId] = current
        commentCounts[trimmedId] = (commentCounts[trimmedId] ?? 0) + 1
        saveCache()

        var payload: [String: AnyJSON] = [
            "title_id": .string(trimmedId),
            "device_id": .string(deviceId),
            "body": .string(trimmedBody),
            "display_name": .string(displayName),
            "initials": .string(initials)
        ]
        if let userId { payload["user_id"] = .string(userId) }

        WatchIntentLogger.shared.log(
            eventType: .commentsOpened,
            titleId: trimmedId,
            metadata: ["action": "post", "body_length": trimmedBody.count]
        )

        do {
            try await SupabaseManager.shared.client
                .from("title_comments")
                .insert(payload)
                .execute()
            // Re-fetch so the optimistic row is replaced by the canonical
            // server record (real id + server-side timestamp).
            await loadComments(titleId: trimmedId)
            return true
        } catch {
            let message = error.localizedDescription
            if message.lowercased().contains("42501") || message.lowercased().contains("row-level security") {
                self.lastError = "Supabase blocked the comment. Open Profile → Diagnostics and run the schema setup SQL."
            } else {
                self.lastError = message
            }
            print("[Social] postComment failed: \(message)")
            // Leave the optimistic row in place so the user still sees what
            // they wrote on this device.
            return false
        }
    }

    // MARK: - Helpers

    private func composedName(first: String?, last: String?) -> String? {
        let f = (first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let l = (last ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [f, l].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// `"some.user@example.com"` → `"some.user"` so we have a sane fallback
    /// display name when the user hasn't entered their real name yet.
    private func handle(from email: String) -> String {
        if let at = email.firstIndex(of: "@") {
            return String(email[..<at])
        }
        return email
    }

    /// Two-letter avatar code mirroring the rules used elsewhere in the app
    /// (Profile avatar ring). Falls back to "G" for guests.
    static func initials(firstName: String?, lastName: String?, displayName: String?) -> String {
        let f = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let l = lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let firstChar = f.first, let lastChar = l.first {
            return "\(firstChar)\(lastChar)".uppercased()
        }
        if let firstChar = f.first {
            return String(firstChar).uppercased()
        }
        let composed = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = composed.split(whereSeparator: { $0.isWhitespace })
        if let first = parts.first?.first, let last = parts.dropFirst().last?.first {
            return "\(first)\(last)".uppercased()
        }
        if let first = parts.first?.first {
            return String(first).uppercased()
        }
        return "G"
    }

    // MARK: - Sign-out cleanup

    /// Clears all in-memory social state and removes the local UserDefaults
    /// cache. Called from `AuthViewModel.signOut()` so the next user starts
    /// with empty likes/comments instead of the previous user's data.
    func clearLocalCache() {
        self.likeCounts = [:]
        self.likedByMe = []
        self.watchedByMe = []
        self.commentCounts = [:]
        self.commentsByTitle = [:]
        self.loadingComments = []
        self.loadingCounts = []
        self.togglingLikes = []
        self.togglingWatched = []
        self.postingComment = []
        UserDefaults.standard.removeObject(forKey: localCacheKey)
    }

    // MARK: - Local cache (small + fast)

    /// Serializable snapshot of the data we want to survive cold launches.
    private struct CacheBlob: Codable {
        let likeCounts: [String: Int]
        let likedByMe: [String]
        let watchedByMe: [String]?
        let commentCounts: [String: Int]
    }

    private func hydrateFromCache() {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey) else { return }
        do {
            let blob = try JSONDecoder().decode(CacheBlob.self, from: data)
            self.likeCounts = blob.likeCounts
            self.commentCounts = blob.commentCounts
            self.likedByMe = Set(blob.likedByMe)
            self.watchedByMe = Set(blob.watchedByMe ?? [])
        } catch {
            print("[Social] cache hydrate failed: \(error.localizedDescription)")
        }
    }

    private func saveCache() {
        let blob = CacheBlob(
            likeCounts: likeCounts,
            likedByMe: Array(likedByMe),
            watchedByMe: Array(watchedByMe),
            commentCounts: commentCounts
        )
        do {
            let data = try JSONEncoder().encode(blob)
            UserDefaults.standard.set(data, forKey: localCacheKey)
        } catch {
            print("[Social] cache save failed: \(error.localizedDescription)")
        }
    }
}
