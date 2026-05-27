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

        let answer = try await callPerplexity(query: trimmed, connectedServices: connectedServices)
        let matches = await resolveTitleMatches(in: answer)

        // Remember the turn for follow-up context.
        transcript.append(Message(role: "user", content: trimmed))
        transcript.append(Message(role: "assistant", content: answer))

        return AgentResponse(answer: answer, matches: matches)
    }

    // MARK: - Perplexity call

    private func callPerplexity(query: String, connectedServices: [String]) async throws -> String {
        let toolkitURL = Config.EXPO_PUBLIC_TOOLKIT_URL.trimmingCharacters(in: .whitespaces)
        let secret = Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY.trimmingCharacters(in: .whitespaces)
        guard !toolkitURL.isEmpty, !secret.isEmpty else {
            throw AgentError.missingSecret
        }
        guard let url = URL(string: "\(toolkitURL)/v2/vercel/v1/chat/completions") else {
            throw AgentError.networkError
        }

        let locale = DeviceLocale.current()
        let region = locale.regionDisplayName

        let services: String = {
            if connectedServices.isEmpty { return "the user hasn't connected any services yet" }
            return connectedServices.map { $0.capitalized }.joined(separator: ", ")
        }()

        let systemPrompt = """
        You are Stream Agent, the AI co-pilot inside GuideStream TV — a streaming guide app. Your job is to recommend movies and TV shows that the user can actually watch RIGHT NOW on a real streaming service.

        Rules you MUST follow:
        1. Only recommend titles that are currently available on a major streaming service (Netflix, Max/HBO, Hulu, Disney+, Apple TV+, Amazon Prime Video, Paramount+, Peacock, Crunchyroll, YouTube TV, etc.). NEVER say "available on streaming services" — name the specific service.
        2. The user is in \(region). Prioritize services and titles available in that region.
        3. The user's connected streaming services: \(services). PREFER titles available on those services and call it out when a recommendation requires a service the user hasn't connected.
        4. Format each recommended title as **Title (Year)** on a line of its own, followed by a one-sentence pitch and the streaming service. Example:
           **The Bear (2022)** — A chaotic, electric kitchen drama. Streaming on Hulu.
        5. Limit to 3-6 recommendations per response. Quality over quantity.
        6. If the user asks a non-recommendation question (a fact about a show, a release date, etc.), answer it directly with one or two sentences and a source URL in parentheses.
        7. Never use [1] [2] citation markers. If you cite a source, write the full https:// URL inline.
        8. Be conversational and concise. No filler. No bullet points unless the user asked for a list.
        """

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        // Replay last 4 turns of memory so follow-ups have context.
        for m in transcript.suffix(8) {
            messages.append(["role": m.role, "content": m.content])
        }
        messages.append(["role": "user", "content": query])

        let body: [String: Any] = [
            "model": "perplexity/sonar-pro",
            "messages": messages,
            "search_recency_filter": "month"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
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
        case 402: throw AgentError.insufficientBalance
        case 429: throw AgentError.rateLimited
        default:
            #if DEBUG
            let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[StreamAgent] HTTP \(http.statusCode): \(bodyStr.prefix(400))")
            #endif
            throw AgentError.serverError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw AgentError.emptyResponse }
        return content
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

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }
}
