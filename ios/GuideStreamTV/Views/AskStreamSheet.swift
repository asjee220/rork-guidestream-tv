//
//  AskStreamSheet.swift
//  GuideStreamTV
//
//  Hybrid Search + AI sheet. The bar auto-switches mode based on what the
//  user types:
//   * Single-word or short queries → TMDB title search (search results list)
//   * Multi-word / question-style queries → Stream Agent AI via Perplexity
//     sonar-pro (search-grounded answers with poster cards for each title
//     the agent recommends)
//
//  Both paths share the bottom sheet, the orange brand chrome, and the
//  same tap-through into the existing ShowDetailScreen.
//

import SwiftUI
import UIKit

enum AskBarMode {
    case idle
    case search
    case ai
}

enum AskSheetState {
    case idle
    case search
    case ai
}

private enum AskFocusField: Hashable {
    case bar
    case composer
}

struct AskChatMessage: Identifiable, Equatable {
    let id = UUID()
    let isUser: Bool
    let text: String
    /// AI-side: titles the agent surfaced for this turn. The renderer
    /// draws a horizontal poster rail under the bubble.
    let matches: [AgentTitleMatchModel]
    /// AI-side: true while we're awaiting Perplexity. The bubble shows
    /// a typing-dots animation instead of text.
    let isPending: Bool
    /// AI-side: true when this is a friendly error so it can be styled
    /// differently (orange instead of grey).
    let isError: Bool

    static func == (lhs: AskChatMessage, rhs: AskChatMessage) -> Bool { lhs.id == rhs.id }
}

/// Plain `Equatable` mirror of `AgentTitleMatch` so the chat message can
/// own its matches without leaking the `Sendable` constraints up the view.
struct AgentTitleMatchModel: Identifiable, Equatable, Hashable {
    let id: Int
    let title: String
    let posterUrl: String?
    let backdropUrl: String?
    let year: Int?
    let isTV: Bool
    let providerName: String?

    init(from match: AgentTitleMatch) {
        self.id = match.id
        self.title = match.tmdb.displayName
        self.posterUrl = match.tmdb.posterUrl
        self.backdropUrl = match.tmdb.backdropUrl
        self.year = match.tmdb.year
        self.isTV = match.tmdb.isTV
        self.providerName = match.providerName
    }
}

struct AskStreamSheet: View {
    let isOpen: Bool
    let onClose: () -> Void
    var onSelectResult: (TMDBResult) -> Void = { _ in }

    @State private var query: String = ""
    @State private var activeFilter: String = "All"
    @State private var messages: [AskChatMessage] = []
    @State private var sheetOffset: CGFloat = 1200
    @State private var keyboardHeight: CGFloat = 0
    @State private var searchResults: [TMDBResult] = []
    @State private var isSearching: Bool = false
    @State private var searchError: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var aiTask: Task<Void, Never>? = nil
    @State private var selectedMatch: AgentTitleMatchModel? = nil
    @State private var auth = AuthViewModel.shared
    @State private var providerByResult: [Int: Platform] = [:]
    @FocusState private var inputFocus: AskFocusField?

    private let suggestions: [String] = [
        "What should I watch tonight?",
        "Shows like Breaking Bad on my services",
        "Build me a binge queue",
        "What's everyone watching this week?",
    ]

    private let filters: [String] = ["All", "Shows", "Movies", "People"]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Scrim
                Color.black.opacity(isOpen ? 0.40 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(isOpen)
                    .onTapGesture { close() }
                    .animation(.easeOut(duration: 0.2), value: isOpen)

                sheetContent(height: geo.size.height * 0.80)
                    .offset(y: sheetOffset - keyboardHeight)
                    .animation(.spring(response: 0.55, dampingFraction: 0.82), value: sheetOffset)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .fullScreenCover(item: $selectedMatch) { match in
            ShowDetailScreen(
                titleId: String(match.id),
                title: match.title,
                posterUrl: match.posterUrl,
                backdropUrl: match.backdropUrl,
                isTV: match.isTV,
                onBack: { selectedMatch = nil }
            )
        }
        .onChange(of: isOpen) { _, newValue in
            if newValue {
                sheetOffset = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if isOpen { inputFocus = .composer }
                }
            } else {
                sheetOffset = 1200
                inputFocus = nil
                searchTask?.cancel()
                aiTask?.cancel()
                StreamAgentService.shared.reset()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if !isOpen {
                        query = ""
                        messages = []
                        activeFilter = "All"
                        searchResults = []
                        providerByResult = [:]
                        searchError = nil
                        isSearching = false
                    }
                }
            }
        }
        .onAppear {
            if isOpen { sheetOffset = 0 }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification),
            perform: handleKeyboardShow
        )
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification),
            perform: handleKeyboardHide
        )
    }

    // MARK: - Keyboard avoidance

    private var keyboardDuration: TimeInterval { 0.25 }

    private func handleKeyboardShow(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? keyboardDuration
        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = frame.height
        }
    }

    private func handleKeyboardHide(_ notification: Notification) {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? keyboardDuration
        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = 0
        }
    }

    // MARK: - Derived

    private var wordCount: Int {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .count
    }

    private var barMode: AskBarMode {
        if query.isEmpty { return .idle }
        // Heuristic: 3+ words OR a question mark = AI mode; otherwise direct
        // title search. Keeps the UX snappy: typing a show name doesn't fire
        // an LLM call, asking "shows like…" does.
        let isQuestion = query.contains("?")
        return (wordCount >= 3 || isQuestion) ? .ai : .search
    }

    private var sheetState: AskSheetState {
        if !messages.isEmpty { return .ai }
        switch barMode {
        case .idle: return .idle
        case .search: return .search
        case .ai: return .ai
        }
    }

    // MARK: - Sheet

    @ViewBuilder
    private func sheetContent(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 40, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 8)

            header
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 0.5),
                    alignment: .bottom
                )

            smartBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Content
            ZStack {
                switch sheetState {
                case .idle: idleContent
                case .search: searchContent
                case .ai: aiContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomInputRow
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24,
                style: .continuous
            )
            .fill(Color(red: 0x0A/255, green: 0x11/255, blue: 0x20/255))
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24,
                style: .continuous
            )
            .stroke(Color.orange.opacity(0.20), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 30, y: -10)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color(red: 0.10, green: 0.30, blue: 0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("S")
                    .font(.guideHeading(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("Stream Agent")
                    .font(.guideHeading(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("AI-powered discovery · Hey Stream")
                    .font(.guideBody(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.40))
            }

            Spacer()

            Button(action: close) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                    Image(systemName: "xmark")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Smart Bar

    private var smartBar: some View {
        HStack(spacing: 10) {
            Image(systemName: barMode == .ai ? "sparkles" : "magnifyingglass")
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(smartBarIconColor)
                .frame(width: 20)

            TextField("", text: $query, prompt: Text("Search or ask anything…")
                .foregroundColor(Color.white.opacity(0.35)))
                .font(.guideBody(size: 14, weight: .regular))
                .foregroundStyle(.white)
                .tint(Color.orange)
                .submitLabel(.send)
                .onSubmit(submitQuery)
                .focused($inputFocus, equals: .bar)

            if query.isEmpty {
                Button {
                    haptic(.light)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.orange)
                        Image(systemName: "mic.fill")
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: submitQuery) {
                    ZStack {
                        Circle()
                            .fill(barMode == .ai ? Color.orange : Color.blue)
                        Image(systemName: "arrow.up")
                            .scaledFont(size: 15, weight: .bold)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(
            Capsule(style: .continuous)
                .fill(smartBarBackground)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(smartBarBorder, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.20), value: barMode)
    }

    private var smartBarBackground: Color {
        switch barMode {
        case .idle: return Color.white.opacity(0.05)
        case .search: return Color.blue.opacity(0.08)
        case .ai: return Color.orange.opacity(0.08)
        }
    }

    private var smartBarBorder: Color {
        switch barMode {
        case .idle: return Color.white.opacity(0.14)
        case .search: return Color.blue.opacity(0.55)
        case .ai: return Color.orange.opacity(0.55)
        }
    }

    private var smartBarIconColor: Color {
        switch barMode {
        case .idle: return Color.white.opacity(0.30)
        case .search: return Color(red: 0x7A/255, green: 0xAB/255, blue: 0xFF/255)
        case .ai: return Color.orange
        }
    }

    // MARK: - Idle Content

    private var idleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // AI Suggestions
                VStack(alignment: .leading, spacing: 10) {
                    Text("Try asking")
                        .font(.guideHeading(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)

                    VStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button {
                                haptic(.light)
                                query = s
                                submitQuery()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "sparkles")
                                        .scaledFont(size: 16, weight: .semibold)
                                        .foregroundStyle(Color.orange)
                                    Text(s)
                                        .font(.guideBody(size: 13, weight: .regular))
                                        .foregroundStyle(Color.white.opacity(0.70))
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.orange.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // How it works hint
                VStack(alignment: .leading, spacing: 6) {
                    Text("HOW IT WORKS")
                        .font(.guideBody(size: 10, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.4))
                    Text("Single titles run a fast search. Questions and longer prompts go to your AI co-pilot.")
                        .font(.guideBody(size: 12))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineSpacing(3)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 16)
            }
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Search Content

    private var searchContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Showing results for \"\(query)\"")
                        .font(.guideBody(size: 12, weight: .regular))
                        .foregroundStyle(Color.textSecondary)
                    if isSearching {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.orange)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if let err = searchError {
                    Text(err)
                        .font(.guideBody(size: 12, weight: .regular))
                        .foregroundStyle(Color.orange.opacity(0.85))
                        .padding(.horizontal, 16)
                } else if !isSearching && searchResults.isEmpty {
                    Text("No matches yet — try a different title.")
                        .font(.guideBody(size: 13, weight: .regular))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                }

                VStack(spacing: 10) {
                    ForEach(searchResults) { r in
                        Button {
                            haptic(.light)
                            WatchIntentLogger.shared.log(
                                eventType: .cardTapped,
                                titleId: String(r.id),
                                metadata: [
                                    "source": "tmdb_search",
                                    "type": r.mediaType ?? "unknown",
                                    "query": query
                                ]
                            )
                            onSelectResult(r)
                        } label: {
                            HStack(spacing: 12) {
                                resultPoster(url: r.posterUrl)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(r.displayName)
                                        .font(.guideHeading(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)

                                    HStack(spacing: 6) {
                                        // Platform badge — the core fragmentation solve
                                        if let platform = providerByResult[r.id] {
                                            Text(platform.name)
                                                .font(.guideBody(size: 10, weight: .bold))
                                                .tracking(0.4)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(
                                                    Capsule().fill(platform.color)
                                                )
                                        } else {
                                            // Skeleton pill while provider is loading
                                            Capsule()
                                                .fill(Color.white.opacity(0.08))
                                                .frame(width: 72, height: 20)
                                        }

                                        if let y = r.year {
                                            Text(String(y))
                                                .font(.guideBody(size: 12, weight: .regular))
                                                .foregroundStyle(Color.textSecondary)
                                        }

                                        let typeLabel = r.isTV ? "TV Series" : "Movie"
                                        Text(typeLabel)
                                            .font(.guideBody(size: 10, weight: .bold))
                                            .foregroundStyle(r.isTV ? Color.blue : Color.orange)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule().fill((r.isTV ? Color.blue : Color.orange).opacity(0.15))
                                            )
                                            .overlay(
                                                Capsule().stroke((r.isTV ? Color.blue : Color.orange).opacity(0.35), lineWidth: 1)
                                            )
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .scaledFont(size: 13, weight: .semibold)
                                    .foregroundStyle(Color.white.opacity(0.30))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 16)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func resultPoster(url: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.35), Color.navy],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            if let urlString = url, let u = URL(string: urlString) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Image(systemName: "film")
                            .scaledFont(size: 18, weight: .regular)
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .allowsHitTesting(false)
            } else {
                Image(systemName: "film")
                    .scaledFont(size: 18, weight: .regular)
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .frame(width: 80, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - AI Content

    private var aiContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Initial greeting
                    agentBubble(text: "Hey! What are you in the mood to watch? I can search across all your services, find hidden gems, or build you a full binge queue.", id: "greeting")

                    ForEach(messages) { m in
                        if m.isUser {
                            userBubble(m.text).id(m.id)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                if m.isPending {
                                    typingBubble().id(m.id)
                                } else {
                                    agentBubble(text: m.text, id: m.id.uuidString, accent: m.isError ? Color.orange : nil)
                                }
                                if !m.matches.isEmpty {
                                    matchPosterRail(matches: m.matches)
                                }
                            }
                        }
                    }

                    // Follow-up suggestions (always show after at least one exchange)
                    if !messages.isEmpty && messages.last?.isPending == false {
                        VStack(spacing: 10) {
                            followUpButton("Only shows I haven't watched")
                            followUpButton("Build me a binge queue")
                        }
                        .padding(.top, 6)
                    }

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: messages.last?.isPending) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func agentBubble(text: String, id: String, accent: Color? = nil) -> some View {
        HStack(alignment: .top) {
            Text(LocalizedStringKey(stripUrls(text)))
                .font(.guideBody(size: 13, weight: .regular))
                .foregroundStyle(accent ?? Color.textSecondary)
                .lineSpacing(4)
                .tint(Color.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 4,
                        bottomLeadingRadius: 14,
                        bottomTrailingRadius: 14,
                        topTrailingRadius: 14,
                        style: .continuous
                    )
                    .fill(accent != nil ? Color.orange.opacity(0.10) : Color.white.opacity(0.07))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .id(id)
    }

    /// Strips bare http(s) URLs so the bubble body doesn't show long
    /// inline citations — Perplexity returns clickable markdown that
    /// renders cleanly thanks to `LocalizedStringKey`.
    private func stripUrls(_ text: String) -> String {
        let pattern = #"\s*\(https?://[^\s)]+\)\s*"#
        return text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 0)
            Text(text)
                .font(.guideBody(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 14,
                        bottomLeadingRadius: 14,
                        bottomTrailingRadius: 4,
                        topTrailingRadius: 14,
                        style: .continuous
                    )
                    .fill(Color.orange)
                )
        }
    }

    /// Three-dot typing indicator shown while the agent is generating.
    private func typingBubble() -> some View {
        HStack(alignment: .top) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .opacity(0.4)
                        .modifier(TypingDotPulse(delay: Double(i) * 0.15))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 4,
                    bottomLeadingRadius: 14,
                    bottomTrailingRadius: 14,
                    topTrailingRadius: 14,
                    style: .continuous
                )
                .fill(Color.white.opacity(0.07))
            )
            Spacer(minLength: 0)
        }
    }

    /// Horizontal scroll of poster cards for titles the agent matched.
    /// Tapping a poster opens the title's detail screen.
    private func matchPosterRail(matches: [AgentTitleMatchModel]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(matches) { m in
                    Button {
                        haptic(.light)
                        WatchIntentLogger.shared.log(
                            eventType: .cardTapped,
                            titleId: String(m.id),
                            platformId: m.providerName?.lowercased() ?? "ai_match",
                            metadata: [
                                "source": "ask_stream_ai_match",
                                "title": m.title
                            ]
                        )
                        selectedMatch = m
                    } label: {
                        AgentMatchCard(match: m)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func followUpButton(_ text: String) -> some View {
        Button {
            haptic(.light)
            sendUser(text)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.blue)
                Text(text)
                    .font(.guideBody(size: 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.60))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.blue.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Input

    private var bottomInputRow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 0.5)

            HStack(spacing: 10) {
                TextField("", text: $query, prompt: Text(bottomPlaceholder)
                    .foregroundColor(Color.white.opacity(0.35)))
                    .font(.guideBody(size: 13, weight: .regular))
                    .foregroundStyle(.white)
                    .focused($inputFocus, equals: .composer)
                    .tint(Color.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .submitLabel(.send)
                    .onSubmit(submitQuery)

                Button(action: submitQuery) {
                    ZStack {
                        Circle().fill(query.isEmpty ? Color.white.opacity(0.08) : Color.orange)
                        Image(systemName: "arrow.up")
                            .scaledFont(size: 14, weight: .bold)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(query.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .padding(.bottom, 20)
        }
    }

    private var bottomPlaceholder: String {
        sheetState == .ai ? "Ask anything about what to watch…" : "Search or ask anything…"
    }

    // MARK: - Actions

    private func submitQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        haptic(.medium)
        WatchIntentLogger.shared.log(
            eventType: .askStreamQuery,
            metadata: [
                "query": trimmed,
                "mode": barModeString,
                "char_count": trimmed.count
            ]
        )
        if barMode == .search {
            WatchIntentLogger.shared.log(
                eventType: .searchQuery,
                metadata: ["query": trimmed, "source": "tmdb"]
            )
            runSearch(trimmed)
            inputFocus = nil
            return
        }
        sendUser(trimmed)
        query = ""
    }

    private func runSearch(_ q: String) {
        searchTask?.cancel()
        isSearching = true
        searchError = nil
        let task = Task {
            do {
                let results = try await TMDBService.shared.searchContent(query: q)
                if Task.isCancelled { return }
                searchResults = results
                Task { await hydrateProviders(for: results) }
                isSearching = false
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                searchError = "Couldn't reach search right now."
                isSearching = false
            }
        }
        searchTask = task
    }

    private var barModeString: String {
        switch barMode {
        case .idle: return "idle"
        case .search: return "search"
        case .ai: return "ai"
        }
    }

    /// Appends the user message + a pending agent bubble, fires the
    /// Perplexity call, then replaces the pending bubble with the real
    /// response (or a friendly error).
    private func hydrateProviders(for results: [TMDBResult]) async {
        let toFetch = results.filter { providerByResult[$0.id] == nil }
        guard !toFetch.isEmpty else { return }
        await withTaskGroup(of: (Int, Platform)?.self) { group in
            for r in toFetch {
                group.addTask {
                    let provider = try? await TMDBService.shared.getTopWatchProvider(
                        tmdbId: r.id, isTV: r.isTV
                    )
                    guard let provider,
                          let platform = Platform.from(providerName: provider.providerName)
                    else { return nil }
                    return (r.id, platform)
                }
            }
            for await pair in group {
                if let (id, platform) = pair {
                    await MainActor.run { providerByResult[id] = platform }
                }
            }
        }
    }

    private func sendUser(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(AskChatMessage(isUser: true, text: trimmed, matches: [], isPending: false, isError: false))
        let pending = AskChatMessage(isUser: false, text: "", matches: [], isPending: true, isError: false)
        messages.append(pending)
        let pendingId = pending.id
        query = ""
        inputFocus = nil

        aiTask?.cancel()
        aiTask = Task { @MainActor in
            do {
                let response = try await StreamAgentService.shared.ask(
                    query: trimmed,
                    connectedServices: Array(auth.selectedServices)
                )
                if Task.isCancelled { return }
                if let idx = messages.firstIndex(where: { $0.id == pendingId }) {
                    messages[idx] = AskChatMessage(
                        isUser: false,
                        text: response.answer,
                        matches: response.matches.map(AgentTitleMatchModel.init(from:)),
                        isPending: false,
                        isError: false
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                let msg = (error as? AgentError)?.errorDescription ?? "Couldn't reach the AI right now. Please try again."
                if let idx = messages.firstIndex(where: { $0.id == pendingId }) {
                    messages[idx] = AskChatMessage(
                        isUser: false,
                        text: msg,
                        matches: [],
                        isPending: false,
                        isError: true
                    )
                }
            }
        }
    }

    private func close() {
        haptic(.light)
        inputFocus = nil
        onClose()
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Match poster card

private struct AgentMatchCard: View {
    let match: AgentTitleMatchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.black
                .frame(width: 124, height: 168)
                .overlay {
                    if let urlString = match.posterUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.35), Color.navy],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .overlay {
                                    Image(systemName: "film")
                                        .scaledFont(size: 20, weight: .regular)
                                        .foregroundStyle(Color.white.opacity(0.45))
                                }
                            }
                        }
                        .allowsHitTesting(false)
                    } else {
                        LinearGradient(
                            colors: [Color.orange.opacity(0.35), Color.navy],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .overlay {
                            Image(systemName: "film")
                                .scaledFont(size: 20, weight: .regular)
                                .foregroundStyle(Color.white.opacity(0.45))
                        }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let provider = match.providerName, !provider.isEmpty {
                        Text(provider.uppercased())
                            .scaledFont(size: 8, weight: .heavy)
                            .tracking(0.4)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.orange)
                            )
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(match.title)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(metaLine)
                    .scaledFont(size: 10)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(width: 124, alignment: .leading)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = match.year { parts.append(String(y)) }
        parts.append(match.isTV ? "Series" : "Movie")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Typing dot animation

private struct TypingDotPulse: ViewModifier {
    let delay: Double
    @State private var animate: Bool = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(animate ? 1.4 : 0.6)
            .opacity(animate ? 1.0 : 0.35)
            .animation(
                .easeInOut(duration: 0.6).repeatForever().delay(delay),
                value: animate
            )
            .onAppear { animate = true }
    }
}

#Preview {
    ZStack {
        Color.navy.ignoresSafeArea()
        AskStreamSheet(isOpen: true, onClose: {})
    }
}
