//
//  ReleaseReminderService.swift
//  GuideStreamTV
//
//  Per-owner "remind me" signal stored in the release_reminders table.
//  Local-first / Supabase write-through mirroring SocialViewModel's ownership
//  pattern: signed-in users own rows via user_id, guests own rows via
//  device_id. Toggling is idempotent thanks to the partial unique indexes
//  (user_id, title_id, reminder_kind) and (device_id, title_id, reminder_kind).
//
//  Two kinds share the table: 'arrival' (title lands on streaming — the
//  original behavior) and 'departure' (saved title is leaving soon).
//

import Foundation
import Supabase

enum ReminderKind: String {
    case arrival
    case departure
}

@MainActor
@Observable
final class ReleaseReminderService {
    static let shared = ReleaseReminderService()

    /// Arrival reminders keyed by title id ("remind me when this lands").
    private(set) var remindedTitleIds: Set<String> = []

    /// Departure reminders keyed by title id ("remind me before this leaves").
    private(set) var departureRemindedTitleIds: Set<String> = []

    private var currentUserId: UUID? {
        AuthViewModel.shared.currentUser?.id
    }

    private init() {}

    /// Arrival-scoped lookup — the original API surface, unchanged.
    func isReminded(_ titleId: String) -> Bool {
        remindedTitleIds.contains(titleId)
    }

    /// Kind-scoped lookup for both arrival and departure reminders.
    func isReminded(_ titleId: String, kind: ReminderKind) -> Bool {
        let set = kind == .arrival ? remindedTitleIds : departureRemindedTitleIds
        return set.contains(titleId)
    }

    /// Queries release_reminders for the given title_id and kind using the
    /// same owner-scoping pattern as SocialViewModel.fetchHasLiked. Updates
    /// the matching set from the count.
    func refreshReminded(titleId: String, kind: ReminderKind = .arrival) async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let deviceId = DeviceIdentity.shared.deviceId
        do {
            var query = SupabaseManager.shared.client
                .from("release_reminders")
                .select("id", head: true, count: .exact)
                .eq("title_id", value: trimmed)
                .eq("reminder_kind", value: kind.rawValue)
            if let uid = currentUserId?.uuidString {
                query = query.eq("user_id", value: uid)
            } else {
                query = query.eq("device_id", value: deviceId)
                    .filter("user_id", operator: "is", value: "null")
            }
            let response = try await query.execute()
            let exists = (response.count ?? 0) > 0
            if kind == .arrival {
                if exists {
                    remindedTitleIds.insert(trimmed)
                } else {
                    remindedTitleIds.remove(trimmed)
                }
            } else {
                if exists {
                    departureRemindedTitleIds.insert(trimmed)
                } else {
                    departureRemindedTitleIds.remove(trimmed)
                }
            }
        } catch {
            print("[ReleaseReminder] refreshReminded failed: \(error.localizedDescription)")
        }
    }

    /// Toggle the reminder for `titleId`. Local state flips immediately so the
    /// UI reacts on the next frame; the Supabase write is best-effort.
    func toggleReminder(
        titleId: String,
        tmdbId: Int?,
        source: String = "reels_coming_soon",
        kind: ReminderKind = .arrival,
        mediaType: String = "movie"
    ) async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let wasReminded = isReminded(trimmed, kind: kind)
        // Optimistic local flip on the kind's set.
        if kind == .arrival {
            if wasReminded {
                remindedTitleIds.remove(trimmed)
            } else {
                remindedTitleIds.insert(trimmed)
            }
        } else {
            if wasReminded {
                departureRemindedTitleIds.remove(trimmed)
            } else {
                departureRemindedTitleIds.insert(trimmed)
            }
        }

        WatchIntentLogger.shared.log(
            eventType: .notifyReleaseTapped,
            titleId: trimmed,
            metadata: ["set": !wasReminded, "source": source, "kind": kind.rawValue]
        )

        let deviceId = DeviceIdentity.shared.deviceId
        let userId = currentUserId?.uuidString
        if wasReminded {
            await removeReminder(titleId: trimmed, userId: userId, deviceId: deviceId, kind: kind)
        } else {
            await insertReminder(
                titleId: trimmed,
                userId: userId,
                deviceId: deviceId,
                tmdbId: tmdbId,
                kind: kind,
                mediaType: mediaType
            )
        }
    }

    // MARK: - Private Supabase writes

    private func insertReminder(
        titleId: String,
        userId: String?,
        deviceId: String,
        tmdbId: Int?,
        kind: ReminderKind,
        mediaType: String
    ) async {
        var payload: [String: AnyJSON] = [
            "title_id": .string(titleId),
            "device_id": .string(deviceId),
            "media_type": .string(mediaType),
            "reminder_kind": .string(kind.rawValue)
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
            // already exists for this owner and kind.
            if message.contains("duplicate") || message.contains("23505") {
                return
            }
            print("[ReleaseReminder] insert failed: \(error.localizedDescription)")
        }
    }

    private func removeReminder(
        titleId: String,
        userId: String?,
        deviceId: String,
        kind: ReminderKind
    ) async {
        do {
            var query = SupabaseManager.shared.client
                .from("release_reminders")
                .delete()
                .eq("title_id", value: titleId)
                .eq("reminder_kind", value: kind.rawValue)
            if let userId {
                query = query.eq("user_id", value: userId)
            } else {
                query = query.eq("device_id", value: deviceId)
                    .filter("user_id", operator: "is", value: "null")
            }
            try await query.execute()
        } catch {
            print("[ReleaseReminder] delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sign-out cleanup

    func clearLocalCache() {
        remindedTitleIds = []
        departureRemindedTitleIds = []
    }
}
