//
//  AppProfileManager.swift
//  GuideStreamTV
//
//  Local "Watch Profile" store — lets a single account split into multiple
//  in-app personas (Main, Kids, Partner, etc.) Netflix-style. Profiles are
//  persisted in `UserDefaults` so they survive launches, but they are not
//  yet synced to Supabase — they live on the device until a server-side
//  profiles table exists.
//

import Foundation
import SwiftUI

/// A single in-app profile (display name, accent color, kid flag).
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

@MainActor
@Observable
final class AppProfileManager {
    static let shared = AppProfileManager()

    private(set) var profiles: [WatchProfile]
    private(set) var activeProfileId: UUID?

    private let profilesKey = "gs.profiles.list"
    private let activeKey = "gs.profiles.active"

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([WatchProfile].self, from: data),
           !decoded.isEmpty {
            self.profiles = decoded
        } else {
            // Seed a single "Main" profile on first launch so the list isn't empty.
            self.profiles = [
                WatchProfile(name: "Main", colorHex: "#F5821F", isKid: false, emoji: "🎬")
            ]
        }
        if let active = defaults.string(forKey: activeKey), let uuid = UUID(uuidString: active),
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

    /// Avatar palette presets used by the "Add Profile" form.
    static let palette: [String] = [
        "#F5821F", // orange
        "#1A6FE8", // blue
        "#22C55E", // green
        "#E11D48", // rose
        "#8B5CF6", // violet
        "#06B6D4", // cyan
        "#F59E0B", // amber
        "#EC4899"  // pink
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
        let profile = WatchProfile(
            name: trimmed,
            colorHex: colorHex,
            isKid: isKid,
            emoji: emoji
        )
        profiles.append(profile)
        persist()
    }

    func update(_ profile: WatchProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        persist()
    }

    func remove(_ id: UUID) {
        // Never let the user end up with zero profiles.
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = profiles.first?.id
        }
        persist()
    }

    /// Removes all watch profiles and the active profile selection from
    /// UserDefaults so the next sign-in starts fresh.
    func clearAll() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: profilesKey)
        defaults.removeObject(forKey: activeKey)
        self.profiles = [
            WatchProfile(name: "Main", colorHex: "#F5821F", isKid: false, emoji: "🎬")
        ]
        self.activeProfileId = profiles.first?.id
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
