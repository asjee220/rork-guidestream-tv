//
//  TVSchemeDiagnosticView.swift
//  GuideStreamTVTV
//
//  TEMPORARY throwaway QA screen. Tests the exact deep-link URLs
//  TVOSDeepLinker.resolve produces for each of the twelve streaming
//  services, and lets a tester open each URL in isolation via
//  UIApplication.shared.open — no openChain, no isLaunchable filtering.
//  Remove after testing.
//

import SwiftUI
import UIKit

struct TVSchemeDiagnosticView: View {

    struct DiagnosticRow: Identifiable {
        let id: String
        let serviceName: String
        let serviceColor: Color
        var titleName: String?
        var matchedSourceName: String?
        var extractedContentId: String?
        var contentURLString: String?
        var playURL: URL?
        var appHomeURL: URL?
        var unavailableReason: String?
        var openAppResult: Bool?
        var openAppNote: String?
        var candidateResults: [String: Bool] = [:]
        var lastPressedURL: String?
    }

    /// One testable URL in the candidate row. `id` is the tag, unique
    /// within a row so ForEach identity is stable across re-renders.
    struct DiagnosticCandidate: Identifiable {
        let id: String
        let tag: String
        let url: URL
    }

    @State private var rows: [DiagnosticRow] = []
    @State private var isLoading: Bool = false
    @Environment(\.dismiss) private var dismiss

    /// Duplicated from TVHomeView.swift so TVHomeView is not modified.
    private let tmdbProviderIdMap: [String: Int] = [
        "netflix": 8,
        "prime": 9,
        "disney": 337,
        "max": 1899,
        "hulu": 15,
        "appletv": 350,
        "paramount": 2303,
        "peacock": 386,
        "starz": 43,
        "showtime": 37,
        "crunchyroll": 283,
        "youtube": 192,
    ]

    var body: some View {
        ZStack {
            TVTheme.backgroundGradient

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if isLoading && rows.isEmpty {
                        HStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Resolving titles for all 12 services\u{2026}")
                                .font(.system(size: 20))
                                .foregroundStyle(TVTheme.textSecondary)
                        }
                        .padding(.horizontal, 80)
                    }

                    ForEach($rows) { $row in
                        rowView(for: $row)
                    }

                    Color.clear.frame(height: 60)
                }
                .padding(.bottom, 40)
                // Focus container for the whole stack so focus can travel
                // from the header Done button down into the service rows.
                .focusSection()
            }
        }
        .task { await loadAll() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scheme Diagnostics")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(.white)
                Text("Throwaway QA — each button calls UIApplication.shared.open once, no fallback.")
                    .font(.system(size: 16))
                    .foregroundStyle(TVTheme.textTertiary)
            }
            Spacer()
            DiagnosticGhostButton {
                dismiss()
            } label: { focused in
                Text("Done")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(focused ? Color.navy : TVTheme.orange)
            }
        }
        .padding(.horizontal, 80)
        .padding(.top, 24)
    }

    // MARK: - Row

    @ViewBuilder
    private func rowView(for row: Binding<DiagnosticRow>) -> some View {
        let r = row.wrappedValue
        let candidates = buildCandidates(
            serviceId: r.id,
            contentURL: r.contentURLString.flatMap { URL(string: $0) },
            playURL: r.playURL,
            contentId: r.extractedContentId
        )

        VStack(alignment: .leading, spacing: 14) {
            // Service name
            HStack(spacing: 12) {
                Circle()
                    .fill(r.serviceColor)
                    .frame(width: 14, height: 14)
                Text(r.serviceName)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
            }

            if let reason = r.unavailableReason {
                Text(reason)
                    .font(.system(size: 16))
                    .foregroundStyle(TVTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Title: \(r.titleName ?? "\u{2014}")")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TVTheme.textPrimary)
                    .lineLimit(2)

                // Matched source name
                if let sourceName = r.matchedSourceName {
                    Text("Matched source: \(sourceName)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TVTheme.textSecondary)
                }

                // Extracted content id
                Text("Content ID: \(r.extractedContentId ?? "no id extracted")")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(r.extractedContentId != nil ? TVTheme.blue : TVTheme.textTertiary)

                urlLabel("contentURL", r.contentURLString)
                urlLabel("playURL", r.playURL?.absoluteString)
                urlLabel("appHomeURL", r.appHomeURL?.absoluteString)

                // Candidate buttons row (Open app + all candidates)
                HStack(spacing: 16) {
                    DiagnosticGhostButton {
                        openURL(r.appHomeURL, binding: row, keyPath: \.openAppResult)
                    } label: { focused in
                        resultButtonLabel("Open app", result: r.openAppResult, note: r.openAppNote, enabled: r.appHomeURL != nil, focused: focused)
                    }

                    ForEach(candidates) { candidate in
                        DiagnosticGhostButton {
                            openCandidate(candidate.url, tag: candidate.tag, binding: row)
                        } label: { focused in
                            resultButtonLabel(candidate.tag, result: r.candidateResults[candidate.tag], enabled: true, focused: focused)
                        }
                    }
                }
                // Focus container so focus can move horizontally across
                // this row's buttons once it has entered the row.
                .focusSection()

                // Mono-spaced last pressed URL
                if let last = r.lastPressedURL {
                    Text(last)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(TVTheme.textTertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TVTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(TVTheme.hairline, lineWidth: 1)
                }
        )
        .padding(.horizontal, 80)
        // Focus container for the row itself so focus can enter the first
        // row and move between rows even though rows sit in a plain VStack
        // inside a ScrollView.
        .focusSection()
    }

    // MARK: - URL label

    @ViewBuilder
    private func urlLabel(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(label):")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TVTheme.textTertiary)
            Text(value ?? "nil")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(value != nil ? TVTheme.blue : TVTheme.textTertiary)
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }

    // MARK: - Button label

    @ViewBuilder
    private func resultButtonLabel(_ title: String, result: Bool?, note: String? = nil, enabled: Bool, focused: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(enabled ? (focused ? Color.navy : .white) : TVTheme.textTertiary)
            if let result {
                Text(result ? "PASS" : "FAIL")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(result ? Color.green : Color.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(result ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    )
            } else if let note {
                // Nil-URL outcome — shown instead of PASS/FAIL so pressing a
                // button with nothing to open still reports visibly.
                Text(note)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TVTheme.textTertiary)
            }
        }
    }

    // MARK: - Open URL (direct, no openChain) — for Open app button

    private func openURL(
        _ url: URL?,
        binding: Binding<DiagnosticRow>,
        keyPath: WritableKeyPath<DiagnosticRow, Bool?>
    ) {
        guard let url else {
            // No .disabled — a disabled button is unfocusable on tvOS and
            // strands focus. Keep the button enabled and report instead.
            binding.wrappedValue.openAppNote = "no URL to test"
            return
        }
        binding.wrappedValue.lastPressedURL = url.absoluteString
        UIApplication.shared.open(url, options: [:]) { success in
            binding.wrappedValue[keyPath: keyPath] = success
        }
    }

    // MARK: - Open candidate URL (direct, no openChain)

    private func openCandidate(
        _ url: URL,
        tag: String,
        binding: Binding<DiagnosticRow>
    ) {
        binding.wrappedValue.lastPressedURL = url.absoluteString
        UIApplication.shared.open(url, options: [:]) { success in
            binding.wrappedValue.candidateResults[tag] = success
        }
    }

    // MARK: - Candidate builder

    /// Builds the ordered list of candidate URLs for a service row.
    /// Candidate 1 ("https"): raw contentURL from Watchmode, no rewriting.
    /// Candidate 2 ("resolver"): playURL from TVOSDeepLinker.resolve.
    /// Candidates 3+: per-service scheme guesses from the extracted content id.
    private func buildCandidates(
        serviceId: String,
        contentURL: URL?,
        playURL: URL?,
        contentId: String?
    ) -> [DiagnosticCandidate] {
        var candidates: [DiagnosticCandidate] = []

        // 1. Raw contentURL — always rendered when present
        if let contentURL {
            candidates.append(DiagnosticCandidate(id: "https", tag: "https", url: contentURL))
        }

        // 2. Resolver playURL — omitted when nil
        if let playURL {
            candidates.append(DiagnosticCandidate(id: "resolver", tag: "resolver", url: playURL))
        }

        // 3. Per-service scheme guesses — omitted when id is nil or not an identifier
        if let contentId, isLikelyIdentifier(contentId) {
            for guess in schemeGuesses(for: serviceId, contentId: contentId) {
                if let url = URL(string: guess.urlString) {
                    candidates.append(DiagnosticCandidate(id: guess.tag, tag: guess.tag, url: url))
                }
            }
        }

        return candidates
    }

    // MARK: - Scheme guesses

    /// Per-service scheme guesses built from the extracted content id.
    /// Returns an empty array for services with no documented schemes.
    private func schemeGuesses(for serviceId: String, contentId: String) -> [(tag: String, urlString: String)] {
        switch serviceId {
        case "peacock":
            return [
                ("peacock:watch", "peacock://watch/\(contentId)"),
                ("peacock:asset", "peacock://asset/\(contentId)")
            ]
        case "disney":
            return [
                ("disney:video", "disneyplus://video/\(contentId)"),
                ("disney:content", "disneyplus://content/\(contentId)")
            ]
        case "paramount":
            return [
                ("paramount:video", "paramountplus://video/\(contentId)"),
                ("paramount:watch", "paramountplus://watch/\(contentId)")
            ]
        case "max":
            return [
                ("max:video", "max://video/\(contentId)"),
                ("hbomax:video", "hbomax://video/\(contentId)")
            ]
        case "prime":
            return [
                ("aiv:resume", "aiv://aiv/resume?asin=\(contentId)"),
                ("prime:watch", "primevideo://watch/\(contentId)")
            ]
        case "appletv":
            return [
                ("videos:show", "videos://tv.apple.com/show/\(contentId)")
            ]
        case "crunchyroll":
            return [
                ("crunchy:media", "crunchyroll://media/\(contentId)")
            ]
        case "starz":
            return [
                ("starz:content", "starz://content/\(contentId)")
            ]
        default:
            return []
        }
    }

    // MARK: - Identifier check

    /// Returns false when the extracted id is a URL path-structure word
    /// (e.g. "watch", "title") rather than a real content identifier.
    private func isLikelyIdentifier(_ id: String) -> Bool {
        let pathWords: Set<String> = [
            "watch", "title", "search", "browse", "results", "show",
            "movie", "series", "season", "episode", "content", "video",
            "media", "asset", "play", "home", "movies", "tv"
        ]
        return !pathWords.contains(id.lowercased())
    }

    // MARK: - Loading

    private func loadAll() async {
        isLoading = true
        rows = []
        let allServices = StreamingCatalog.all
        let allIds = allServices.map(\.id)

        for service in allServices {
            var row = DiagnosticRow(
                id: service.id,
                serviceName: service.name,
                serviceColor: service.color,
                titleName: nil,
                matchedSourceName: nil,
                extractedContentId: nil,
                contentURLString: nil,
                playURL: nil,
                appHomeURL: nil,
                unavailableReason: nil
            )

            guard let providerId = tmdbProviderIdMap[service.id] else {
                row.unavailableReason = "No TMDB provider id mapped for \u{201c}\(service.id)\u{201d}"
                rows.append(row)
                continue
            }

            let popular = await TVTMDBService.shared.getPopularOnService(tmdbProviderId: providerId)
            guard let firstResult = popular.first else {
                row.unavailableReason = "getPopularOnService(providerId: \(providerId)) returned no results"
                rows.append(row)
                continue
            }

            row.titleName = firstResult.displayName

            let resolved = await TVWatchmodeResolver.shared.resolve(
                tmdbId: firstResult.id,
                isTV: true,
                season: nil,
                episode: nil,
                subscribedServices: allIds,
                episodePlatformHint: nil
            )

            guard let resolved else {
                row.unavailableReason = "TVWatchmodeResolver returned nil for tmdbId \(firstResult.id)"
                rows.append(row)
                continue
            }

            // Find the source matching this service.
            // 1. Exact match via Platform.from(providerName:)?.catalogId
            // 2. Fallback: first source whose name, lowercased, contains the
            //    catalogue service name as a substring — so "STARZ (Via Hulu)"
            //    matches "Starz" and "Crunchyroll Premium" matches "Crunchyroll".
            let serviceNameLower = service.name.lowercased()

            let exactMatch = resolved.usSources.first { source in
                Platform.from(providerName: source.name)?.catalogId == service.id
            } ?? resolved.primarySource.flatMap { primary in
                guard Platform.from(providerName: primary.name)?.catalogId == service.id
                else { return nil as TVWatchmodeResolver.TVResolvedSource? }
                return primary
            }

            let matchingSource = exactMatch ?? resolved.usSources.first { source in
                source.name.lowercased().contains(serviceNameLower)
            } ?? resolved.primarySource.flatMap { primary in
                guard primary.name.lowercased().contains(serviceNameLower)
                else { return nil as TVWatchmodeResolver.TVResolvedSource? }
                return primary
            }

            guard let source = matchingSource else {
                let names = resolved.usSources.map(\.name).joined(separator: ", ")
                row.unavailableReason = "No resolved source matching \u{201c}\(service.name)\u{201d}. Sources: [\(names)]"
                rows.append(row)
                continue
            }

            row.matchedSourceName = source.name

            let contentURL = source.webUrl.flatMap { URL(string: $0) }
            row.contentURLString = source.webUrl
            row.extractedContentId = TVOSDeepLinker.extractContentId(from: contentURL)

            let target = TVOSDeepLinker.resolve(
                platform: source.name,
                title: firstResult.displayName,
                contentURL: contentURL
            )

            row.playURL = target.playURL
            row.appHomeURL = target.appHomeURL

            rows.append(row)
        }

        isLoading = false
    }
}

// MARK: - Ghost secondary control

/// Orange-outlined ghost button used by every control on this screen
/// (Done, Open app, and each candidate). Mirrors GhostButton in
/// SportsView.swift: orange text inside a 2pt orange rounded outline on
/// a clear background, inverting to a filled orange pill with dark text
/// when focused. Focus is read with @FocusState bound to the Button —
/// the pattern proven to track focus on this platform — instead of the
/// broken @Environment(\.isFocused)-inside-a-ButtonStyle approach.
private struct DiagnosticGhostButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: (_ isFocused: Bool) -> Label

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            label(isFocused)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isFocused ? TVTheme.orange : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(TVTheme.orange, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isFocused)
    }
}
