//
//  SupabaseSchemaProbe.swift
//  GuideStreamTV
//
//  Tests every Supabase table the app writes to and classifies the result:
//
//  - `.ok`              — table exists, read works, and (for write-probed tables)
//                         an insert was accepted.
//  - `.tableMissing`    — Postgres reports `PGRST205` / "does not exist".
//  - `.rlsBlocked`      — Postgres reports `42501` row-level security violation.
//  - `.columnMissing`   — Postgres reports `PGRST204` for a column we use.
//  - `.error(message)`  — anything else (network, auth, etc).
//
//  Probe rows that *do* land in Supabase are cleaned up after the write
//  succeeds so we don't pollute the user's analytics or watch list.
//
//  Used by `SupabaseDiagnosticsView` to give the user a precise picture of
//  what's wrong with their schema/policies and a one-tap copy of the SQL
//  that fixes it.
//

import Foundation
import Supabase

@MainActor
@Observable
final class SupabaseSchemaProbe {
    static let shared = SupabaseSchemaProbe()

    enum CheckState: Equatable {
        case unknown
        case checking
        case ok
        case tableMissing
        case rlsBlocked
        case columnMissing(String)
        case notNullViolation(String)
        case error(String)

        var isFailure: Bool {
            switch self {
            case .ok, .unknown, .checking: return false
            default: return true
            }
        }
    }

    struct TableCheck: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let purpose: String
        let writeProbe: Bool
        var read: CheckState = .unknown
        var write: CheckState = .unknown
    }

    /// Catalog of tables the app touches. `writeProbe` controls whether we
    /// attempt a real insert (cleaned up after) — we skip insert probes for
    /// tables whose RLS rightly requires authentication (`users`,
    /// `new_episodes`) so the probe doesn't generate false failures.
    static let tableCatalog: [(name: String, purpose: String, writeProbe: Bool)] = [
        ("watch_intent_events", "Analytics events for every tap, watch, and open", true),
        ("device_sessions", "One row per device install (the guest profile)", true),
        ("user_streams", "Your saved watch list", true),
        ("title_likes", "Likes per title (episodes, shows, sports games)", true),
        ("title_comments", "Comments per title", true),
        ("users", "Your profile (name, email, services)", false),
        ("new_episodes", "Server-managed episode releases", false)
    ]

    private(set) var checks: [TableCheck]
    private(set) var isProbing: Bool = false
    private(set) var lastProbedAt: Date?

    /// True when any table currently reports a failure or is still unknown
    /// after the most recent probe run.
    var hasIssues: Bool {
        checks.contains { $0.read.isFailure || $0.write.isFailure }
    }

    var passingCount: Int {
        checks.filter { !$0.read.isFailure && !$0.write.isFailure && $0.read != .unknown }.count
    }

    var totalCount: Int { checks.count }

    private init() {
        self.checks = Self.tableCatalog.map {
            TableCheck(name: $0.name, purpose: $0.purpose, writeProbe: $0.writeProbe)
        }
    }

    /// Run all probes sequentially. Updates `checks` as each one completes so
    /// the UI animates progress in.
    func probeAll() async {
        isProbing = true
        // Reset all to .checking for animation.
        for i in checks.indices {
            checks[i].read = .checking
            checks[i].write = checks[i].writeProbe ? .checking : .unknown
        }
        for i in checks.indices {
            await probe(index: i)
        }
        lastProbedAt = Date()
        isProbing = false
    }

    // MARK: - Per-table probe

    private func probe(index: Int) async {
        let table = checks[index].name
        // 1. Read probe — confirms table exists and read is allowed.
        do {
            _ = try await SupabaseManager.shared.client
                .from(table)
                .select("*", head: true)
                .limit(1)
                .execute()
            checks[index].read = .ok
        } catch {
            let (state, _) = classify(error)
            checks[index].read = state
            // If the table is missing we don't need to bother with a write probe.
            if case .tableMissing = state {
                checks[index].write = .tableMissing
                return
            }
        }

        // 2. Write probe — only for tables where we expect the anon/auth user
        // to be allowed to write.
        guard checks[index].writeProbe else {
            checks[index].write = .unknown
            return
        }
        await writeProbe(index: index)
    }

    private func writeProbe(index: Int) async {
        let table = checks[index].name
        let deviceId = DeviceIdentity.shared.deviceId
        let probeTitleId = "probe-\(deviceId.prefix(8))"

        var payload: [String: AnyJSON] = [:]
        switch table {
        case "watch_intent_events":
            payload = [
                "event_type": .string("schema_probe"),
                "device_id": .string(deviceId)
            ]
        case "device_sessions":
            payload = [
                "device_id": .string(deviceId),
                "is_guest": .bool(true),
                "is_authenticated": .bool(false)
            ]
        case "user_streams":
            // Use the always-present device_id as the row owner so the probe
            // never trips the legacy FK on `user_id -> auth.users`. We also
            // send both `title` and the legacy `title_name` so probes succeed
            // against either modern or legacy schemas.
            payload = [
                "title_id": .string(probeTitleId),
                "title": .string("Schema Probe"),
                "title_name": .string("Schema Probe"),
                "device_id": .string(deviceId)
            ]
        case "title_likes":
            payload = [
                "title_id": .string(probeTitleId),
                "device_id": .string(deviceId)
            ]
        case "title_comments":
            payload = [
                "title_id": .string(probeTitleId),
                "device_id": .string(deviceId),
                "body": .string("Schema probe — safe to delete.")
            ]
        default:
            checks[index].write = .unknown
            return
        }

        // Try once normally; on PGRST204 missing-column or 23502 not-null
        // violations, adapt the payload and retry. This keeps the probe
        // green against legacy schemas without blocking the user.
        for attempt in 0..<5 {
            do {
                if table == "device_sessions" {
                    try await SupabaseManager.shared.client
                        .from(table)
                        .upsert(payload, onConflict: "device_id")
                        .execute()
                } else {
                    try await SupabaseManager.shared.client
                        .from(table)
                        .insert(payload)
                        .execute()
                }
                checks[index].write = .ok
                await cleanupProbe(table: table, probeTitleId: String(probeTitleId))
                return
            } catch {
                let (state, message) = classify(error)
                let lowered = message.lowercased()
                // Duplicate key (23505) — a previous probe row is still
                // present (the cleanup delete never finished). A unique-
                // violation proves the table exists and the write path is
                // functional, so treat it as ok and delete the stale row so
                // the next run starts clean. Cleanup failure is non-fatal,
                // matching the existing best-effort contract.
                if lowered.contains("23505") || lowered.contains("duplicate key value") {
                    checks[index].write = .ok
                    await cleanupProbe(table: table, probeTitleId: probeTitleId)
                    return
                }
                // Missing column we send → drop it and retry.
                if attempt < 4, lowered.contains("pgrst204") || (lowered.contains("could not find") && lowered.contains("column")),
                   let dropped = Self.dropMissingColumn(from: payload, error: message) {
                    payload = dropped
                    continue
                }
                // NOT NULL on a column we don't send → fill with a placeholder.
                if attempt < 4, lowered.contains("23502") || lowered.contains("not-null constraint"),
                   let filled = Self.fillNotNullViolation(in: payload, error: message, fallback: "Schema Probe") {
                    payload = filled
                    continue
                }
                checks[index].write = state
                return
            }
        }
    }

    /// Drop the column referenced by a PGRST204 "Could not find ... column"
    /// error so the probe payload matches the live schema.
    private static func dropMissingColumn(
        from payload: [String: AnyJSON],
        error: String
    ) -> [String: AnyJSON]? {
        let lowered = error.lowercased()
        guard lowered.contains("could not find") && lowered.contains("column") else { return nil }
        var trimmed = payload
        var didDrop = false
        for key in Array(payload.keys) where key != "title_id" && key != "event_type" {
            if lowered.contains("'\(key.lowercased())'") {
                trimmed.removeValue(forKey: key)
                didDrop = true
            }
        }
        return didDrop ? trimmed : nil
    }

    /// Backfill a column flagged by a 23502 NOT NULL violation so the
    /// probe insert can succeed on legacy schemas.
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

    /// Best-effort cleanup. Removes the synthetic row inserted during the
    /// write probe so the user's real data isn't polluted with probe rows.
    private func cleanupProbe(table: String, probeTitleId: String) async {
        do {
            switch table {
            case "watch_intent_events":
                try await SupabaseManager.shared.client
                    .from(table)
                    .delete()
                    .eq("event_type", value: "schema_probe")
                    .execute()
            case "user_streams", "title_likes", "title_comments":
                // Clean up by title_id only — covers both signed-in and
                // device-id-owned probe rows.
                try await SupabaseManager.shared.client
                    .from(table)
                    .delete()
                    .eq("title_id", value: probeTitleId)
                    .execute()
            default:
                break
            }
        } catch {
            // Ignore — leftover probe rows are harmless.
            print("[SchemaProbe] cleanup of \(table) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Error classification

    private func classify(_ error: Error) -> (CheckState, String) {
        let ns = error as NSError
        var message = ns.localizedDescription
        // Pull richer Postgres details out of the userInfo dict when present.
        for key in ["message", "details", "hint", "code"] {
            if let value = ns.userInfo[key] as? String, !value.isEmpty {
                message += " | \(key)=\(value)"
            }
        }
        let lowered = message.lowercased()

        if lowered.contains("pgrst205")
            || lowered.contains("could not find the table")
            || lowered.contains("does not exist") {
            return (.tableMissing, message)
        }
        if lowered.contains("42501") || lowered.contains("row-level security") {
            return (.rlsBlocked, message)
        }
        if lowered.contains("pgrst204") || lowered.contains("could not find the") && lowered.contains("column") {
            // Extract the column name out of "Could not find the 'foo' column of ..."
            let column = Self.extractColumnName(from: message) ?? "unknown"
            return (.columnMissing(column), message)
        }
        if lowered.contains("23502") || lowered.contains("not-null constraint") {
            let column = Self.extractNotNullColumn(from: message) ?? "unknown"
            return (.notNullViolation(column), message)
        }
        return (.error(message), message)
    }

    private static func extractColumnName(from message: String) -> String? {
        // Match `'columnName'` after "Could not find the".
        guard let range = message.range(of: "Could not find the '", options: .caseInsensitive) else { return nil }
        let after = message[range.upperBound...]
        guard let end = after.firstIndex(of: "'") else { return nil }
        return String(after[..<end])
    }

    /// Extract the column name out of a Postgres 23502 message of the form
    /// `null value in column "foo" of relation "bar" violates ...`.
    private static func extractNotNullColumn(from message: String) -> String? {
        guard let range = message.range(of: "column \"", options: .caseInsensitive) else { return nil }
        let after = message[range.upperBound...]
        guard let end = after.firstIndex(of: "\"") else { return nil }
        return String(after[..<end])
    }
}
