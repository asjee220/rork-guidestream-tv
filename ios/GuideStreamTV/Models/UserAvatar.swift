//
//  UserAvatar.swift
//  GuideStreamTV
//
//  What `users.avatar_url` can hold, and how every client reads it.
//
//  The column is a single text field, so it carries two different things and
//  the prefix is what tells them apart:
//
//    "https://…/storage/v1/object/public/avatars/<uid>/<file>"  an upload
//    "preset:popcorn"                                            a built-in
//    null / empty                                                initials
//
//  Presets exist because tvOS has no file picker and no photo library — an
//  Apple TV viewer could otherwise never change their avatar at all. They are
//  drawn from a symbol and a gradient rather than shipped as image assets, so
//  the same eight choices render identically on iOS, tvOS and Android without
//  adding a single binary to any of the three apps. The `id` strings are the
//  contract between platforms: change one here and it must change in
//  AvatarPreset.kt and the tvOS copy in the same commit.
//

import SwiftUI

/// A built-in avatar: an SF Symbol on a two-colour gradient.
struct AvatarPreset: Identifiable, Hashable, Sendable {
    let id: String
    let symbol: String
    let colors: [Color]

    /// The value written to `users.avatar_url` for this preset.
    var storageValue: String { "preset:\(id)" }

    static let all: [AvatarPreset] = [
        AvatarPreset(id: "popcorn", symbol: "popcorn.fill",
                     colors: [Color(hex: "F5821F"), Color(hex: "C2410C")]),
        AvatarPreset(id: "film", symbol: "film.fill",
                     colors: [Color(hex: "6366F1"), Color(hex: "3730A3")]),
        AvatarPreset(id: "tv", symbol: "tv.fill",
                     colors: [Color(hex: "0EA5E9"), Color(hex: "0C4A6E")]),
        AvatarPreset(id: "star", symbol: "star.fill",
                     colors: [Color(hex: "FACC15"), Color(hex: "A16207")]),
        AvatarPreset(id: "bolt", symbol: "bolt.fill",
                     colors: [Color(hex: "A855F7"), Color(hex: "6B21A8")]),
        AvatarPreset(id: "heart", symbol: "heart.fill",
                     colors: [Color(hex: "EC4899"), Color(hex: "9D174D")]),
        AvatarPreset(id: "moon", symbol: "moon.stars.fill",
                     colors: [Color(hex: "38BDF8"), Color(hex: "1E3A8A")]),
        AvatarPreset(id: "rocket", symbol: "airplane",
                     colors: [Color(hex: "22C55E"), Color(hex: "14532D")]),
    ]

    static func named(_ id: String) -> AvatarPreset? {
        all.first { $0.id == id }
    }
}

/// A parsed `users.avatar_url`. `nil` means the viewer has not chosen one and
/// the initials monogram stands.
enum UserAvatar: Equatable, Sendable {
    case uploaded(URL)
    case preset(String)

    /// Parses the stored column value. Anything unrecognised — an empty
    /// string, a malformed URL, a preset id this build does not know — reads as
    /// `nil` so an older client silently falls back to initials rather than
    /// rendering a broken image.
    static func parse(_ raw: String?) -> UserAvatar? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("preset:") {
            let id = String(value.dropFirst("preset:".count))
            return AvatarPreset.named(id) != nil ? .preset(id) : nil
        }
        guard value.hasPrefix("https://") || value.hasPrefix("http://"),
              let url = URL(string: value) else { return nil }
        return .uploaded(url)
    }

    var preset: AvatarPreset? {
        if case let .preset(id) = self { return AvatarPreset.named(id) }
        return nil
    }
}
