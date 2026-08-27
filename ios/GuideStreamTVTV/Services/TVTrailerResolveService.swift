//
//  TVTrailerResolveService.swift
//  GuideStreamTVTV
//
//  Client for the `trailer_resolve` Supabase edge function — the same
//  resolver the iPhone and Android Reels feeds use, ported to the tvOS
//  target (deployed with verify_jwt=false, so the anon key is enough and
//  no user session is needed).
//
//  TMDB reports which trailer keys exist for a title but never whether a
//  key will actually play: an owner may have made the video private,
//  region-blocked it, or left it unprocessed. That information is not in
//  the TMDB payload, so no client-side ranking can recover it. The server
//  verifies each candidate against the YouTube Data API and returns only
//  keys that are public, processed, embeddable and not US-blocked, in rank
//  order.
//
//  It matters more here than on the phone. tvOS cannot embed a player, so
//  every key has to survive extraction as well — and extraction is slow.
//  Spending it on a key the server already knows is dead is the difference
//  between a hero that plays and one that falls back to its poster.
//

import Foundation

nonisolated enum TVTrailerResolveService {
    /// Shape returned by the `trailer_resolve` edge function. Only `keys` is
    /// used here — the `videos` subset exists for the phone's Reels feed,
    /// which gives each tier-0/1 video its own reel.
    private struct Response: Decodable {
        let ok: Bool
        let keys: [String]
    }

    /// Verified playable YouTube keys for a title, in server rank order.
    ///
    /// The optional is load-bearing and the two empty cases must not be
    /// conflated:
    ///  * `[]` on any HTTP 200 means the server checked and this title has
    ///    no playable trailer. Do not fall back — there is nothing to find.
    ///  * `nil` means the call itself failed (transport, non-200, decode).
    ///    Fall back to `trailer_cache` / TMDB so a brief Supabase outage
    ///    does not empty the hero.
    static func resolve(tmdbId: Int, isTV: Bool) async -> [String]? {
        let base = TVSupabaseConfig.url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(base)/functions/v1/trailer_resolve") else { return nil }

        let body: [String: Any] = [
            "tmdb_id": tmdbId,
            "media_type": isTV ? "tv" : "movie"
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(TVSupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(TVSupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return nil
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return decoded.keys
    }
}
