//
//  DeviceLocale.swift
//  GuideStreamTV
//
//  Resolves the device's region / language so every TMDB and Watchmode call
//  in the app can be localised. A user in Spain should see Movistar+ /
//  Movistar Plus titles, a user in the UK should see BBC / ITV, a user in
//  Australia should see Stan / Binge — using the user's region for both the
//  content discovery feeds AND the watch-provider lookup is what makes news,
//  trending, and binge rails feel like a local product.
//
//  We intentionally keep this dead-simple: the system `Locale.current`
//  reflects the user's Settings → General → Language & Region choice, and
//  is what every Apple TV / iOS streaming-service app uses to pick its
//  default region too. No remote IP geolocation, no permissions prompts.
//

import Foundation

/// Device-aware locale snapshot used by news, watch-provider lookups, and
/// any other API call that takes a region/language hint.
nonisolated struct DeviceLocale: Sendable, Equatable {
    /// Two-letter ISO 3166-1 alpha-2 country code (e.g. "US", "GB", "DE").
    /// Falls back to "US" when the device locale is missing or unsupported.
    let region: String
    /// BCP-47 language tag in TMDB's expected format (e.g. "en-US", "pt-BR",
    /// "de-DE"). Falls back to "en-US".
    let tmdbLanguage: String

    /// Resolved at call-time so a user changing region in Settings doesn't
    /// require a restart.
    static func current() -> DeviceLocale {
        let locale = Locale.current
        let region = locale.region?.identifier ?? Locale.Region("US").identifier
        let language = locale.language.languageCode?.identifier ?? "en"
        return DeviceLocale(
            region: region.uppercased(),
            tmdbLanguage: "\(language)-\(region.uppercased())"
        )
    }

    /// Human-readable label for the resolved region (e.g. "United States",
    /// "United Kingdom"). Used by the diagnostics screen so users can
    /// confirm what region the app thinks they're in.
    var regionDisplayName: String {
        Locale.current.localizedString(forRegionCode: region) ?? region
    }
}
