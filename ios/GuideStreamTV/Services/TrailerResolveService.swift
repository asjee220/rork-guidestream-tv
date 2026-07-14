//
//  TrailerResolveService.swift
//  GuideStreamTV
//
//  Client for the `trailer_resolve` Supabase edge function (deployed with
//  verify_jwt=false, so the anon key is sufficient and no user session is
//  needed).
//
//  TMDB reports which trailer keys exist for a title but never whether a key
//  will actually play: an owner may have disabled embedding, made the video
//  private, or region-blocked it. No client-side ranking can fix that because
//  the information isn't in the TMDB payload. The server-side resolver verifies
//  each candidate against the YouTube Data API and returns only keys that are
//  embeddable, public, processed, and not blocked in the US, in rank order — so
//  the Reels feed can trust the first key will play.
//
//  Uses the same anon-key POST header pattern as
//  `StreamAgentService.callAskStream`.
//

import Foundation

nonisolated enum TrailerResolveService {
    /// Shape returned by the `trailer_resolve` edge function.
    private struct Response: Decodable {
        let ok: Bool
        let cached: Bool
        let keys: [String]
    }

    /// Resolves the verified, playable YouTube trailer keys for a title in
    /// server rank order.
    ///
    /// The optional return is deliberately load-bearing and the two cases must
    /// never be conflated:
    ///  * Returns the decoded `keys` array on any HTTP 200 — **including an
    ///    empty array**, which is the server telling us this title has no
    ///    playable trailer at all (the caller drops it from the feed).
    ///  * Returns `nil` only when the call itself fails — a transport error, a
    ///    non-200 status, or a decode failure (the caller degrades to the
    ///    unverified TMDB key so a brief Supabase outage doesn't empty the feed).
    static func resolve(tmdbId: Int, isTV: Bool) async -> [String]? {
        let base = SupabaseConfig.url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(base)/functions/v1/trailer_resolve") else { return nil }

        let body: [String: Any] = [
            "tmdb_id": tmdbId,
            "media_type": isTV ? "tv" : "movie"
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
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
