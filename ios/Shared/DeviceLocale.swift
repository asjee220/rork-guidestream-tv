//
//  DeviceLocale.swift
//  GuideStreamTV (SHARED target — must compile into BOTH iOS and tvOS)
//
//  Resolves the device's region / language so every TMDB call in the app
//  can be localised. A user in Spain should see Movistar+ titles and Spanish
//  metadata, a user in the UK should see BBC / ITV — using the user's region
//  for both content discovery feeds AND watch-provider lookup.
//
//  UserDefaults overrides on "gs_preferred_locale" and "gs_content_region"
//  let the app force a language/region without changing device settings.
//  Both default to nil (use device locale). Falls back to "en-US"/"US".
//
//  RORK MAX NOTE: this file lives in the SHARED group so both iOS and tvOS
//  targets compile it. It has no UIKit/SwiftUI imports.
//

import Foundation

nonisolated struct DeviceLocale: Sendable, Equatable {
    /// Two-letter ISO 3166-1 alpha-2 country code (e.g. "US", "GB", "DE").
    /// Falls back to "US" when the device locale is missing or unsupported.
    let region: String
    /// BCP-47 language tag in TMDB's expected format (e.g. "en-US", "pt-BR",
    /// "de-DE"). Falls back to "en-US".
    let tmdbLanguage: String

    /// Resolved at call-time so a user changing region in Settings doesn't
    /// require a restart. UserDefaults overrides take priority over the
    /// device locale; both default to nil.
    static func current() -> DeviceLocale {
        let defaults = UserDefaults.standard

        // Region: content_region override → device → "US"
        let region: String
        if let override = defaults.string(forKey: "gs_content_region") {
            region = override.uppercased()
        } else {
            let deviceRegion = Locale.current.region?.identifier ?? "US"
            region = deviceRegion.uppercased()
        }

        // Language: preferred_locale override (expanded to BCP-47) → device → "en-{region}"
        let tmdbLanguage: String
        if let override = defaults.string(forKey: "gs_preferred_locale") {
            if override.contains("-") {
                tmdbLanguage = override
            } else {
                tmdbLanguage = "\(override)-\(region)"
            }
        } else {
            // The language MUST come from `Locale.preferredLanguages`, not from
            // `Locale.current`. `Locale.current` reports the locale iOS resolved
            // FOR THE APP: the user's preferred-language list intersected with the
            // localizations present in the bundle. Per Apple QA1828, when none of
            // the user's preferred languages are supported by the app, iOS falls
            // back to `CFBundleDevelopmentRegion`. This bundle ships English only,
            // so `Locale.current.language` collapses to "en" on every device and a
            // Spanish user in Spain requests "en-ES" — right region, wrong language.
            // `Locale.preferredLanguages` is the user's raw Settings choice and is
            // independent of what the bundle supports.
            let preferred = Locale.preferredLanguages.first ?? "en"
            let language = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
            tmdbLanguage = "\(language)-\(region)"
        }

        return DeviceLocale(region: region, tmdbLanguage: tmdbLanguage)
    }

    /// Human-readable label for the resolved region (e.g. "United States",
    /// "United Kingdom"). Used by the diagnostics screen so users can
    /// confirm what region the app thinks they're in.
    var regionDisplayName: String {
        Locale.current.localizedString(forRegionCode: region) ?? region
    }
}
