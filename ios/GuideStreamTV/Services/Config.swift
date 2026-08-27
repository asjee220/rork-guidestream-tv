//
//  Config.swift
//  GuideStreamTV
//
//  Client-side build configuration.
//
//  History: RorkMax generated this type from environment variables during its
//  own builds, and `ios/.gitignore` ignored it alongside `.env`, so it was
//  never checked in. Local Xcode builds have no such generation step, which
//  left the iOS app unable to compile on a clean checkout —
//  `ContentSourcesService` references `Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL`
//  at two call sites and nothing defined it. It is now tracked.
//
//  Only values that are safe to ship inside the app binary belong here — the
//  same rule `SupabaseConfig` in SupabaseManager.swift already follows with the
//  project URL and publishable key. Anything genuinely secret must stay
//  server-side; a client-side constant is readable by anyone with the .ipa.
//

import Foundation

enum Config {
    /// Base URL of the Cloudflare Worker in `functions/` (its routes include
    /// `/search/creators` and `/enrich/creators`).
    ///
    /// **Empty until the deployed Worker URL is filled in here.** While empty,
    /// `ContentSourcesService.searchCreatorsLive` returns `[]` by design and
    /// creator search falls back to local results — the app builds and runs
    /// normally, it just doesn't reach the Worker.
    private static let defaultFunctionsURL = ""

    /// Resolved Worker base URL. An `EXPO_PUBLIC_RORK_FUNCTIONS_URL` key in
    /// Info.plist takes precedence when present and non-empty, so a build
    /// setting can vary it per configuration (debug vs release, staging vs
    /// production) without editing this file. Falls back to
    /// `defaultFunctionsURL`.
    static let EXPO_PUBLIC_RORK_FUNCTIONS_URL: String = {
        if let value = Bundle.main.object(
            forInfoDictionaryKey: "EXPO_PUBLIC_RORK_FUNCTIONS_URL"
        ) as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return defaultFunctionsURL
    }()
}
