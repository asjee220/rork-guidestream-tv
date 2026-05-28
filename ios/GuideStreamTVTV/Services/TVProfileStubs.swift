//
//  TVProfileStubs.swift
//  GuideStreamTVTV
//
//  Bridges between the rich iOS profile/devices/account services and the
//  lean tvOS surface. tvOS views were ported from iOS and reference these
//  types directly — rather than rewriting every view, we provide compatible
//  stubs / typealiases that keep the API surface intact so the code
//  compiles and runs cleanly on Apple TV. Network calls fall back to the
//  shared TVSupabaseManager client where applicable.
//

import SwiftUI
import Foundation

// MARK: - Singleton typealiases

typealias DeviceIdentity = TVDeviceIdentity
typealias SupabaseManager = TVSupabaseManager

// MARK: - Device session row (Decodable mirror)

/// Mirror of the iOS `DeviceSessionRow` schema so the tvOS Devices screen
/// can decode rows from the shared `device_sessions` Supabase table.
nonisolated struct DeviceSessionRow: Decodable, Sendable, Identifiable, Hashable {
    let device_id: String
    let device_model: String?
    let os_version: String?
    let app_version: String?
    let build_number: String?
    let last_seen_at: String?
    let first_seen_at: String?
    let is_authenticated: Bool?
    let is_guest: Bool?
    let session_count: Int?

    var id: String { device_id }
}

// MARK: - WatchProfile

struct WatchProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// Hex (e.g. "#F5821F") — stored as string so the struct stays Codable.
    var colorHex: String
    var isKid: Bool
    var emoji: String

    init(id: UUID = UUID(), name: String, colorHex: String, isKid: Bool, emoji: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isKid = isKid
        self.emoji = emoji
    }

    var color: Color { Color(hex: colorHex) }
}

// MARK: - AppProfileManager

@MainActor
@Observable
final class AppProfileManager {
    static let shared = AppProfileManager()

    private(set) var profiles: [WatchProfile]
    private(set) var activeProfileId: UUID?

    private let profilesKey = "gs.tv.profiles.list"
    private let activeKey = "gs.tv.profiles.active"

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([WatchProfile].self, from: data),
           !decoded.isEmpty {
            self.profiles = decoded
        } else {
            self.profiles = [
                WatchProfile(name: "Main", colorHex: "#F5821F", isKid: false, emoji: "🎬")
            ]
        }
        if let active = defaults.string(forKey: activeKey),
           let uuid = UUID(uuidString: active),
           profiles.contains(where: { $0.id == uuid }) {
            self.activeProfileId = uuid
        } else {
            self.activeProfileId = profiles.first?.id
        }
        persist()
    }

    var activeProfile: WatchProfile? {
        guard let id = activeProfileId else { return profiles.first }
        return profiles.first(where: { $0.id == id }) ?? profiles.first
    }

    static let palette: [String] = [
        "#F5821F", "#1A6FE8", "#22C55E", "#E11D48",
        "#8B5CF6", "#06B6D4", "#F59E0B", "#EC4899"
    ]

    static let emojis: [String] = [
        "🎬", "🍿", "🎮", "👑", "🚀", "🌙", "⭐️", "🔥", "🦊", "🐼"
    ]

    func setActive(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        persist()
    }

    func addProfile(name: String, colorHex: String, isKid: Bool, emoji: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let profile = WatchProfile(name: trimmed, colorHex: colorHex, isKid: isKid, emoji: emoji)
        profiles.append(profile)
        persist()
    }

    func update(_ profile: WatchProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        persist()
    }

    func remove(_ id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = profiles.first?.id
        }
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
        if let id = activeProfileId {
            defaults.set(id.uuidString, forKey: activeKey)
        }
    }
}

// MARK: - DeviceSessionService (no-op)

/// tvOS stub: the Apple TV install doesn't actively push `device_sessions`
/// rows, so all calls are no-ops. The session count is still tracked in
/// UserDefaults so the Devices screen can render this device synthetically.
@MainActor
final class DeviceSessionService {
    static let shared = DeviceSessionService()

    private(set) var lastError: String?
    private(set) var lastSuccessAt: Date?
    private(set) var lastAttemptAt: Date?
    private(set) var totalUpserts: Int = 0
    private(set) var totalSuccesses: Int = 0
    private(set) var lastReason: String?

    private let sessionCountKey = "gs.tv.sessionCount"

    private init() {}

    var sessionCount: Int {
        UserDefaults.standard.integer(forKey: sessionCountKey)
    }

    func incrementSessionAndUpsert() {
        let next = sessionCount + 1
        UserDefaults.standard.set(next, forKey: sessionCountKey)
    }

    func upsert(reason: String) {
        lastReason = reason
        lastAttemptAt = Date()
        totalUpserts += 1
    }

    func upsertNowReturningError(reason: String = "diagnostic") async -> String? {
        lastReason = reason
        lastAttemptAt = Date()
        totalUpserts += 1
        return nil
    }
}

// MARK: - ProfileStatsService

@MainActor
@Observable
final class ProfileStatsService {
    static let shared = ProfileStatsService()

    var showsCount: Int = UserDefaults.standard.integer(forKey: "gs.tv.stats.showsCount")
    var hoursWatched: Double = UserDefaults.standard.double(forKey: "gs.tv.stats.hoursWatched")
    var devicesCount: Int = max(1, UserDefaults.standard.integer(forKey: "gs.tv.stats.devicesCount"))
    var isRefreshing: Bool = false
    var lastError: String?

    private init() {}

    var servicesCount: Int {
        AuthViewModel.shared.selectedServices.count
    }

    /// Stub refresh — tvOS doesn't drive Supabase reads for stats, so this
    /// just keeps cached UserDefaults values without flickering.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        // No-op for tvOS.
    }
}

// MARK: - SupabaseSchemaProbe (no-op stub)

/// tvOS stub: shared views on iOS show a setup banner when Supabase tables
/// are missing. The Apple TV install doesn't actively manage the schema, so
/// every probe simply reports `.unknown` and the banner stays hidden.
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

    private(set) var checks: [TableCheck] = []
    private(set) var isProbing: Bool = false
    private(set) var lastProbedAt: Date?

    var hasIssues: Bool { false }
    var passingCount: Int { 0 }
    var totalCount: Int { 0 }

    private init() {}

    /// No-op for tvOS — the Apple TV install doesn't drive schema probes.
    func probeAll() async {
        lastProbedAt = Date()
    }
}

// MARK: - SupabaseDiagnosticsView (placeholder)

/// Minimal placeholder so the Help & Feedback "App Diagnostics" link still
/// has a destination on tvOS. Surfaces a small status panel rather than
/// the full Supabase diagnostics screen from the iOS app.
struct SupabaseDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.navy.ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "waveform.path.ecg")
                    .scaledFont(size: 36, weight: .regular)
                    .foregroundStyle(Color.green)
                    .padding(.top, 8)

                Text("App Diagnostics")
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(.white)

                Text("Device ID")
                    .scaledFont(size: 11, weight: .semibold)
                    .tracking(0.8)
                    .foregroundStyle(Color.textTertiary)
                Text(DeviceIdentity.shared.deviceId)
                    .scaledFont(size: 13, weight: .semibold, design: .monospaced)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 16)

                Text("Sessions on this device")
                    .scaledFont(size: 11, weight: .semibold)
                    .tracking(0.8)
                    .foregroundStyle(Color.textTertiary)
                Text("\(DeviceSessionService.shared.sessionCount)")
                    .scaledFont(size: 16, weight: .bold)
                    .foregroundStyle(.white)

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.orange)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
        }
        .preferredColorScheme(.dark)
    }
}
