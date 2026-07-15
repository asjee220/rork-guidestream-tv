//
//  ReleaseReminderService.swift
//  GuideStreamTV
//
//  Per-owner "remind me when this lands on streaming" signal stored in the
//  release_reminders table. Local-first / Supabase write-through mirroring
//  SocialViewModel's ownership pattern: signed-in users own rows via user_id,
//  guests own rows via device_id. Toggling is idempotent thanks to the partial
//  unique index on the table.
//

import Foundation
import Supabase

@MainActor
@Observable
final class ReleaseReminderService {
    static let shared = ReleaseReminderService()

    private(set) var remindedTitleIds: Set<String> = []

    private var currentUserId: UUID? {
        AuthViewModel.shared.currentUser?.id
    }

    private init() {}

    func isReminded(_ titleId: String) -> Bool {
        remindedTitleIds.contains(titleId)
    }

    /// Queries release_reminders for the given title_id using the same
    /// owner-scoping pattern as SocialViewModel.fetchHasLiked. Updates
    /// `remindedTitleIds` from the count.
    func refreshReminded(titleId: String) async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let deviceId = DeviceIdentity.shared.deviceId
        do {
            var query = SupabaseManager.shared.client
                .from("release_reminders")
                .select("id", head: true, count: .exact)
                .eq("title_id", value: trimmed)
            if let uid = currentUserId?.uuidString {
                query = query.or("user_id.eq.\(uid),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            let response = try await query.execute()
            let exists = (response.count ?? 0) > 0
            if exists {
                remindedTitleIds.insert(trimmed)
            } else {
                remindedTitleIds.remove(trimmed)
            }
        } catch {
            print("[ReleaseReminder] refreshReminded failed: \(error.localizedDescription)")
        }
    }

    /// Toggle the reminder for `titleId`. Local state flips immediately so the
    /// UI reacts on the next frame; the Supabase write is best-effort.
    func toggleReminder(titleId: String, tmdbId: Int?, source: String = "reels_coming_soon") async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let wasReminded = remindedTitleIds.contains(trimmed)
        // Optimistic local flip.
        if wasReminded {
            remindedTitleIds.remove(trimmed)
        } else {
            remindedTitleIds.insert(trimmed)
        }

        WatchIntentLogger.shared.log(
            eventType: .notifyReleaseTapped,
            titleId: trimmed,
            metadata: ["set": !wasReminded, "source": source]
        )

        let deviceId = DeviceIdentity.shared.deviceId
        let userId = currentUserId?.uuidString
        if wasReminded {
            await removeReminder(titleId: trimmed, userId: userId, deviceId: deviceId)
        } else {
            await insertReminder(titleId: trimmed, userId: userId, deviceId: deviceId, tmdbId: tmdbId)
        }
    }

    // MARK: - Private Supabase writes

    private func insertReminder(titleId: String, userId: String?, deviceId: String, tmdbId: Int?) async {
        var payload: [String: AnyJSON] = [
            "title_id": .string(titleId),
            "device_id": .string(deviceId),
            "media_type": .string("movie")
        ]
        if let userId { payload["user_id"] = .string(userId) }
        if let tmdbId { payload["tmdb_id"] = .integer(tmdbId) }
        do {
            try await SupabaseManager.shared.client
                .from("release_reminders")
                .insert(payload)
                .execute()
        } catch {
            let message = error.localizedDescription.lowercased()
            // Duplicate is fine — the partial unique index means the row
            // already exists for this owner.
            if message.contains("duplicate") || message.contains("23505") {
                return
            }
            print("[ReleaseReminder] insert failed: \(error.localizedDescription)")
        }
    }

    private func removeReminder(titleId: String, userId: String?, deviceId: String) async {
        do {
            var query = SupabaseManager.shared.client
                .from("release_reminders")
                .delete()
                .eq("title_id", value: titleId)
            if let userId {
                query = query.or("user_id.eq.\(userId),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            try await query.execute()
        } catch {
            print("[ReleaseReminder] delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sign-out cleanup

    func clearLocalCache() {
        remindedTitleIds = []
    }
}
