//
//  MacAskView.swift
//  GuideStreamTVMac
//
//  AskStream on Mac. Same `askstream` edge function, request shape and
//  title matching as the iPhone's StreamAgentService: the reply's **bold**
//  titles are looked up on TMDB and shown as cards under the answer.
//

import SwiftUI
import Supabase

struct MacAgentMatch: Identifiable, Hashable {
    let result: TVTMDBResult
    let providerName: String?
    var id: Int { result.id }
}

struct MacAgentMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
    var matches: [MacAgentMatch] = []
}

@MainActor
@Observable
final class MacAskService {
    static let shared = MacAskService()
    private init() {}

    var messages: [MacAgentMessage] = []
    var isThinking = false
    var error: String?

    func reset() { messages.removeAll(); error = nil }

    func ask(_ raw: String) async {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isThinking else { return }
        messages.append(MacAgentMessage(isUser: true, text: query))
        isThinking = true
        error = nil
        defer { isThinking = false }
        WatchIntentLogger.shared.log(eventType: .askStreamQuery, metadata: ["query": query, "surface": "mac"])
        do {
            let (reply, blocked) = try await call(query: query)
            let matches = blocked ? [] : await resolveMatches(in: reply)
            messages.append(MacAgentMessage(isUser: false, text: reply, matches: matches))
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach AskStream. Try again."
        }
    }

    private enum AskError: LocalizedError {
        case network, auth, rateLimited, server, empty
        var errorDescription: String? {
            switch self {
            case .network: return "Couldn't reach the AI service. Check your connection and try again."
            case .auth: return "AI features are currently unavailable. Please restart the app."
            case .rateLimited: return "Too many requests right now — give it a moment and try again."
            case .server: return "Something went wrong on our end. Please try again."
            case .empty: return "The agent didn't have an answer for that — try rephrasing?"
            }
        }
    }

    private struct Reply: Decodable { let reply: String?; let blocked: Bool? }

    private func call(query: String) async throws -> (String, Bool) {
        guard let url = URL(string: "\(TVSupabaseConfig.url)/functions/v1/askstream") else { throw AskError.network }
        let token = (try? await SupabaseManager.shared.client.auth.session)?.accessToken ?? TVSupabaseConfig.anonKey
        // Prior turns (up to 8), excluding the question just appended.
        var history: [[String: String]] = messages.dropLast().suffix(8).map {
            ["role": $0.isUser ? "user" : "assistant", "content": $0.text]
        }
        history.append(["role": "user", "content": query])
        var body: [String: Any] = ["messages": history, "device_id": TVDeviceIdentity.shared.deviceId]
        let services = Array(AuthViewModel.shared.selectedServices)
        if !services.isEmpty { body["connected_services"] = services }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(TVSupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) } catch { throw AskError.network }
        guard let http = response as? HTTPURLResponse else { throw AskError.network }
        switch http.statusCode {
        case 200: break
        case 401: throw AskError.auth
        case 429: throw AskError.rateLimited
        case 500...599: throw AskError.server
        default: throw AskError.network
        }
        let decoded = try JSONDecoder().decode(Reply.self, from: data)
        let reply = (decoded.reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw AskError.empty }
        return (reply, decoded.blocked ?? false)
    }

    /// **Title (Year)** spans in the reply, resolved on TMDB (max 6).
    private func resolveMatches(in text: String) async -> [MacAgentMatch] {
        guard let regex = try? NSRegularExpression(pattern: "\\*\\*([^*]+?)\\*\\*") else { return [] }
        let ns = text as NSString
        let names: [(String, Int?)] = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, raw.count <= 120 else { return nil }
            if let r = raw.range(of: #"\((\d{4})\)\s*$"#, options: .regularExpression) {
                let name = String(raw[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : (name, Int(String(raw[r]).filter(\.isNumber)))
            }
            return (raw, nil)
        }
        let found = await withTaskGroup(of: (Int, MacAgentMatch?).self) { group in
            for (index, candidate) in names.prefix(6).enumerated() {
                group.addTask {
                    guard let results = try? await TVTMDBService.shared.searchContent(query: candidate.0),
                          !results.isEmpty else { return (index, nil) }
                    let lowered = candidate.0.lowercased()
                    let pick = results.first { $0.displayName.lowercased() == lowered }
                        ?? candidate.1.flatMap { y in results.first { $0.year == y } }
                        ?? results[0]
                    let provider = try? await TVTMDBService.shared.getTopWatchProvider(tmdbId: pick.id, isTV: pick.isTV)
                    return (index, MacAgentMatch(result: pick, providerName: provider?.providerName))
                }
            }
            var out: [(Int, MacAgentMatch)] = []
            for await (i, m) in group { if let m { out.append((i, m)) } }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var seen = Set<Int>()
        return found.filter { seen.insert($0.id).inserted }
    }
}

struct MacAskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onOpenTitle: (MacTitleRef) -> Void
    @State private var service = MacAskService.shared
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let suggestions = [
        "Something like Severance on my services",
        "A funny movie under 2 hours",
        "What's new this week worth watching?",
        "Best docuseries on Netflix right now",
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(MacColor.orange)
                Text("Ask GuideStream").font(.system(size: 17, weight: .bold))
                Spacer()
                if !service.messages.isEmpty {
                    Button("New chat") { service.reset() }.buttonStyle(.plain).foregroundStyle(MacColor.text2)
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider().overlay(MacColor.hairline)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if service.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Ask for a mood, a genre, or something like a show you love. Answers use your services.")
                                    .font(.system(size: 13)).foregroundStyle(MacColor.text2)
                                ForEach(suggestions, id: \.self) { s in
                                    Button { send(s) } label: {
                                        Text(s).font(.system(size: 13, weight: .medium))
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(MacColor.surface, in: Capsule())
                                            .overlay(Capsule().stroke(MacColor.hairline, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        ForEach(service.messages) { m in bubble(m).id(m.id) }
                        if service.isThinking {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(MacColor.text2) }
                                .font(.system(size: 13)).id("thinking")
                        }
                        if let error = service.error {
                            Text(error).font(.system(size: 12)).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                        }
                    }
                    .padding(18)
                }
                .onChange(of: service.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(service.messages.last?.id, anchor: .bottom) }
                }
            }

            Divider().overlay(MacColor.hairline)
            HStack(spacing: 10) {
                TextField("Ask anything about what to watch", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { send(draft) }
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(draft.isEmpty ? Color.white.opacity(0.15) : MacColor.orange, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || service.isThinking)
            }
            .padding(14)
        }
        .frame(width: 640, height: 680)
        .background(MacColor.navy)
        .onAppear { focused = true }
    }

    private func send(_ text: String) {
        let q = text
        draft = ""
        Task { await service.ask(q) }
    }

    @ViewBuilder private func bubble(_ m: MacAgentMessage) -> some View {
        if m.isUser {
            HStack {
                Spacer(minLength: 80)
                Text(m.text).font(.system(size: 14))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(MacColor.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text((try? AttributedString(markdown: m.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(m.text))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .textSelection(.enabled)
                    .lineSpacing(3)
                if !m.matches.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(m.matches) { match in
                                MacPosterCard(title: match.result.displayName,
                                              subtitle: match.providerName, posterUrl: match.result.posterUrl,
                                              width: 120) {
                                    dismiss()
                                    let ref = MacTitleRef(result: match.result)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onOpenTitle(ref) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
