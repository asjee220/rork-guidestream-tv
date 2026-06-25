//
//  StreamAgentService.swift
//  GuideStreamTV
//
//  Hybrid Search + AI service that powers the AskStream sheet.
//
//  Architecture:
//    * Short / single-word queries → TMDB `search/multi` (direct title match,
//      fast, no LLM cost). The bar already routes these via `submitQuery`.
//    * Multi-word / question queries → Perplexity `sonar-pro` via the Rork
//      proxy. Sonar-pro searches the live web so it knows what's actually
//      streaming today, which services have which titles, and recent
//      Rotten Tomatoes / IMDB scores. The system prompt steers it toward
//      the user's connected services and away from titles that aren't on
//      a real streaming platform.
//    * After Perplexity returns prose with embedded title names, we attempt
//      a TMDB lookup for each detected title so the sheet can render real
//      poster art + a tap-through into the existing ShowDetailScreen.
//
//  Failure mode: every error surfaces a friendly message in the chat
//  bubble instead of crashing the sheet. Rate limits / auth failures from
//  the proxy are explicitly caught and mapped.
//

import Foundation
import Supabase

/// One title surfaced inside an agent reply. Carries enough to render a
/// poster card AND tap through to the existing detail sheet via the
/// shared `TMDBResult` shape.
nonisolated struct AgentTitleMatch: Identifiable, Sendable, Hashable {
    let id: Int
    let tmdb: TMDBResult
    let providerName: String?
}

/// Result of one Stream Agent turn — the raw assistant prose plus a list
/// of TMDB-matched titles the renderer can show as poster cards.
nonisolated struct AgentResponse: Sendable {
    let answer: String
    let matches: [AgentTitleMatch]
    /// True when at least one title was successfully matched to TMDB. The
    /// sheet uses this to decide whether to render a "Found N titles" chip.
    var hasMatches: Bool { !matches.isEmpty }
}

/// Errors the agent surfaces in the UI. Plain enough to map straight to a
/// chat bubble.
enum AgentError: LocalizedError {
    case missingSecret
    case authError
    case rateLimited
    case insufficientBalance
    case networkError
    case serverError(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingSecret:
            return "AI features aren't configured yet. Please try again later."
        case .authError:
            return "AI features are currently unavailable. Please restart the app."
        case .rateLimited:
            return "Too many requests right now — give it a moment and try again."
        case .insufficientBalance:
            return "AI features are temporarily unavailable. Please try again later."
        case .networkError:
            return "Couldn't reach the AI service. Check your connection and try again."
        case .serverError:
            return "Something went wrong on our end. Please try again."
        case .emptyResponse:
            return "The agent didn't have an answer for that — try rephrasing?"
        }
    }
}

@MainActor
final class StreamAgentService {
    static let shared = StreamAgentService()
    private init() {}

    /// Conversation memory for the active sheet. Cleared when the sheet
    /// closes (via `reset()`).
    private var transcript: [Message] = []

    struct Message: Sendable {
        let role: String
        let content: String
    }

    func reset() { transcript.removeAll() }

    /// Ask the agent a natural-language question. Returns the assistant's
    /// reply prose AND a list of TMDB-matched titles for rich UI.
    func ask(
        query: String,
        connectedServices: [String]
    ) async throws -> AgentResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AgentError.emptyResponse }

        let answer = try await callAskStream(query: trimmed, connectedServices: connectedServices)
        let matches = await resolveTitleMatches(in: answer)

        // Remember the turn for follow-up context.
        transcript.append(Message(role: "user", content: trimmed))
        transcript.append(Message(role: "assistant", content: answer))

        return AgentResponse(answer: answer, matches: matches)
    }

    // MARK: - AskStream call

    /// Calls the app's own Claude-powered Supabase edge function (`askstream`),
    /// which applies auth, rate limiting, a topical gate, a scoped system
    /// prompt, and grounding on the user's follows, then returns a plain-text
    /// answer. All soft blocks (off-topic, rate-limited, at-capacity, etc.)
    /// come back as HTTP 200 with a friendly `reply`, so we simply surface it.
    private func callAskStream(query: String, connectedServices: [String]) async throws -> String {
        let base = SupabaseConfig.url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(base)/functions/v1/askstream") else {
            throw AgentError.networkError
        }

        // Prefer the signed-in user's access token so the function can scope
        // grounding + rate limits to the real user; fall back to the anon key
        // (with device_id) for guests.
        let accessToken = (try? await SupabaseManager.shared.client.auth.session)?.accessToken
        let bearer = accessToken ?? SupabaseConfig.anonKey

        // Recent conversation window, then the current query as the final turn
        // so the last message is always the user's.
        var messages: [[String: String]] = []
        for m in transcript.suffix(8) {
            messages.append(["role": m.role, "content": m.content])
        }
        messages.append(["role": "user", "content": query])

        var body: [String: Any] = [
            "messages": messages,
            "device_id": DeviceIdentity.shared.deviceId
        ]
        if !connectedServices.isEmpty {
            body["connected_services"] = connectedServices
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AgentError.networkError
        }

        guard let http = response as? HTTPURLResponse else { throw AgentError.networkError }
        switch http.statusCode {
        case 200: break
        case 401: throw AgentError.authError
        case 429: throw AgentError.rateLimited
        case 500...599: throw AgentError.serverError(http.statusCode)
        default:
            #if DEBUG
            let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[AskStream] HTTP \(http.statusCode): \(bodyStr.prefix(400))")
            #endif
            throw AgentError.networkError
        }

        let decoded = try JSONDecoder().decode(AskStreamResponse.self, from: data)
        let reply = (decoded.reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw AgentError.emptyResponse }
        return reply
    }

    // MARK: - Title extraction + TMDB resolution

    /// Pulls **Bolded** title candidates out of the agent reply and runs
    /// each through TMDB so we can render real posters under the bubble.
    /// Caps at 6 matches to keep the API budget tight.
    private func resolveTitleMatches(in answer: String) async -> [AgentTitleMatch] {
        let candidates = Self.extractTitles(from: answer)
        guard !candidates.isEmpty else { return [] }
        let trimmed = Array(candidates.prefix(6))

        let resolved: [AgentTitleMatch] = await withTaskGroup(of: AgentTitleMatch?.self) { group in
            for candidate in trimmed {
                group.addTask {
                    do {
                        // Search by title; pick the best match with a year proximity check.
                        let results = try await TMDBService.shared.searchContent(query: candidate.name)
                        guard let pick = Self.bestMatch(results, candidate: candidate) else { return nil }
                        let provider = try? await TMDBService.shared.getTopWatchProvider(
                            tmdbId: pick.id,
                            isTV: pick.isTV
                        )
                        return AgentTitleMatch(
                            id: pick.id,
                            tmdb: pick,
                            providerName: provider?.providerName
                        )
                    } catch {
                        return nil
                    }
                }
            }
            var out: [AgentTitleMatch] = []
            var seenIds: Set<Int> = []
            for await m in group {
                guard let m, !seenIds.contains(m.id) else { continue }
                seenIds.insert(m.id)
                out.append(m)
            }
            return out
        }

        return resolved
    }

    /// Title candidate parsed from the agent prose. We capture an optional
    /// year so we can disambiguate franchise reboots (e.g. *The Bear* the
    /// 2022 series vs the 1989 movie).
    nonisolated struct TitleCandidate: Sendable {
        let name: String
        let year: Int?
    }

    /// Extracts bolded titles from Perplexity's markdown reply. We look
    /// for `**Title (Year)**` and `**Title**` patterns.
    nonisolated static func extractTitles(from text: String) -> [TitleCandidate] {
        let pattern = "\\*\\*([^*]+?)\\*\\*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m -> TitleCandidate? in
            guard m.numberOfRanges >= 2 else { return nil }
            let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            // Reject empty captures and obvious non-titles.
            guard !raw.isEmpty, raw.count <= 120 else { return nil }
            // Try to split "Title (2024)" into name + year.
            if let yearRange = raw.range(of: #"\((\d{4})\)\s*$"#, options: .regularExpression) {
                let name = String(raw[..<yearRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let yearStr = String(raw[yearRange]).filter(\.isNumber)
                let year = Int(yearStr)
                if !name.isEmpty {
                    return TitleCandidate(name: name, year: year)
                }
            }
            return TitleCandidate(name: raw, year: nil)
        }
    }

    /// Picks the TMDB result that best matches a candidate name + year.
    nonisolated private static func bestMatch(_ results: [TMDBResult], candidate: TitleCandidate) -> TMDBResult? {
        guard !results.isEmpty else { return nil }
        // Exact name match wins; then year proximity; then popularity (already in TMDB order).
        let lowered = candidate.name.lowercased()
        let exact = results.first { $0.displayName.lowercased() == lowered }
        if let exact { return exact }
        if let year = candidate.year {
            let byYear = results.first { ($0.year ?? -1) == year }
            if let byYear { return byYear }
        }
        return results.first
    }

    // MARK: - Response decoding

    /// Shape returned by the `askstream` edge function. All soft blocks come
    /// back as HTTP 200 with a friendly `reply`; the other flags are advisory.
    private struct AskStreamResponse: Decodable {
        let reply: String?
        let blocked: Bool?
        let reason: String?
        let error: Bool?
        let configured: Bool?
    }
}
