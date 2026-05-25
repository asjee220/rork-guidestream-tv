//
//  AskStreamSheet.swift
//  GuideStreamTV
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

struct AskChatMessage: Identifiable, Equatable {
    let id = UUID()
    let isUser: Bool
    let text: String
    /// AI special response with bolded match count
    let isMatchResult: Bool
}

struct AskStreamSheet: View {
    let isOpen: Bool
    let onClose: () -> Void

    @State private var query: String = ""
    @State private var activeFilter: String = "All"
    @State private var messages: [AskChatMessage] = []
    @State private var sheetOffset: CGFloat = 1200
    @State private var searchResults: [TMDBResult] = []
    @State private var isSearching: Bool = false
    @State private var searchError: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var selectedResult: TMDBResult? = nil
    @FocusState private var inputFocused: Bool

    private let trendingPosters: [(title: String, platform: String, colors: [Color])] = [
        ("The Bear", "FX", [Color(red: 0.85, green: 0.25, blue: 0.15), Color(red: 0.45, green: 0.05, blue: 0.05)]),
        ("Severance", "Apple TV+", [Color(red: 0.10, green: 0.25, blue: 0.50), Color(red: 0.02, green: 0.05, blue: 0.18)]),
        ("Shōgun", "FX", [Color(red: 0.40, green: 0.05, blue: 0.10), Color(red: 0.10, green: 0.02, blue: 0.05)]),
    ]

    private let suggestions: [String] = [
        "What should I watch tonight?",
        "Shows like Breaking Bad on my services",
        "Build me a binge queue",
    ]

    private let filters: [String] = ["All", "Shows", "Movies", "People"]

    private let mockResults: [(title: String, meta: String, owned: Bool, colors: [Color])] = [
        ("Breaking Bad", "Netflix · Drama", true, [Color(red: 0.55, green: 0.20, blue: 0.15), Color(red: 0.10, green: 0.05, blue: 0.02)]),
        ("Better Call Saul", "Netflix · Drama", true, [Color(red: 0.45, green: 0.30, blue: 0.10), Color(red: 0.10, green: 0.07, blue: 0.02)]),
        ("Ozark", "Netflix · Thriller", true, [Color(red: 0.10, green: 0.25, blue: 0.30), Color(red: 0.02, green: 0.05, blue: 0.10)]),
        ("Yellowstone", "Paramount+ · Drama", false, [Color(red: 0.30, green: 0.15, blue: 0.05), Color(red: 0.10, green: 0.05, blue: 0.02)]),
        ("Succession", "HBO · Drama", true, [Color(red: 0.25, green: 0.10, blue: 0.35), Color(red: 0.05, green: 0.02, blue: 0.10)]),
    ]

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
                    .offset(y: sheetOffset)
                    .animation(.spring(response: 0.55, dampingFraction: 0.82), value: sheetOffset)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .fullScreenCover(item: $selectedResult) { result in
            ShowDetailScreen(
                titleId: String(result.id),
                title: result.displayName,
                posterUrl: result.posterUrl,
                backdropUrl: result.backdropUrl,
                isTV: result.isTV,
                onBack: { selectedResult = nil }
            )
        }
        .onChange(of: isOpen) { _, newValue in
            if newValue {
                sheetOffset = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if isOpen { inputFocused = true }
                }
            } else {
                sheetOffset = 1200
                inputFocused = false
                searchTask?.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if !isOpen {
                        query = ""
                        messages = []
                        activeFilter = "All"
                        searchResults = []
                        searchError = nil
                        isSearching = false
                    }
                }
            }
        }
        .onAppear {
            if isOpen { sheetOffset = 0 }
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
        return wordCount >= 3 ? .ai : .search
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
                        .font(.system(size: 14, weight: .semibold))
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(smartBarIconColor)
                .frame(width: 20)

            TextField("", text: $query, prompt: Text("Search or ask anything…")
                .foregroundColor(Color.white.opacity(0.35)))
                .font(.guideBody(size: 14, weight: .regular))
                .foregroundStyle(.white)
                .tint(Color.orange)
                .submitLabel(.send)
                .onSubmit(submitQuery)

            if query.isEmpty {
                Button {
                    haptic(.light)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.orange)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14, weight: .semibold))
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
                            .font(.system(size: 15, weight: .bold))
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
                // Trending
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trending on Your Services")
                        .font(.guideHeading(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        ForEach(trendingPosters.indices, id: \.self) { i in
                            let p = trendingPosters[i]
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        LinearGradient(colors: p.colors, startPoint: .top, endPoint: .bottom)
                                    )
                                    .frame(width: 100, height: 140)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                Text(p.title)
                                    .font(.guideBody(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(p.platform)
                                    .font(.guideBody(size: 10, weight: .regular))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            .frame(width: 100)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // AI Suggestions
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI Suggestions")
                        .font(.guideHeading(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)

                    VStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button {
                                haptic(.light)
                                query = s
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 16, weight: .semibold))
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

                // Filter chips
                HStack(spacing: 8) {
                    ForEach(filters, id: \.self) { f in
                        Button {
                            haptic(.light)
                            activeFilter = f
                        } label: {
                            Text(f)
                                .font(.guideBody(size: 12, weight: .semibold))
                                .foregroundStyle(activeFilter == f ? .white : Color.white.opacity(0.60))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(activeFilter == f ? Color.orange : Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 16)
            }
            .padding(.top, 8)
        }
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
                            selectedResult = r
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
                                        if let y = r.year {
                                            Text(String(y))
                                                .font(.guideBody(size: 12, weight: .regular))
                                                .foregroundStyle(Color.textSecondary)
                                        }
                                        let typeLabel = r.isTV ? "TV" : "Movie"
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
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.30))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .allowsHitTesting(false)
            } else {
                Image(systemName: "film")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .frame(width: 56, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func ownedChip(owned: Bool) -> some View {
        if owned {
            Text("In your services")
                .font(.guideBody(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 0x34/255, green: 0xC7/255, blue: 0x59/255))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color(red: 0x34/255, green: 0xC7/255, blue: 0x59/255).opacity(0.15))
                )
        } else {
            Text("Not subscribed")
                .font(.guideBody(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.white.opacity(0.08))
                )
        }
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
                        } else if m.isMatchResult {
                            matchResultBubble(id: m.id)
                        } else {
                            agentBubble(text: m.text, id: m.id.uuidString)
                        }
                    }

                    // Follow-up suggestions (always show after at least one exchange)
                    if messages.count >= 2 {
                        VStack(spacing: 10) {
                            followUpButton("Only shows I haven't watched")
                            followUpButton("Build me a binge queue from these")
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
        }
    }

    private func agentBubble(text: String, id: String) -> some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.guideBody(size: 13, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .lineSpacing(4)
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
                    .fill(Color.white.opacity(0.07))
                )
                .frame(maxWidth: .infinity * 0.85, alignment: .leading)
            Spacer(minLength: 0)
        }
        .id(id)
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

    private func matchResultBubble(id: UUID) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                (
                    Text("Found ")
                        .foregroundColor(Color.textSecondary)
                    + Text("8 matches")
                        .foregroundColor(Color.orange)
                        .bold()
                    + Text(" across your services — intense character-driven dramas with no filler and protagonists you can't look away from.")
                        .foregroundColor(Color.textSecondary)
                )
                .font(.guideBody(size: 13, weight: .regular))
                .lineSpacing(4)

                Button {
                    haptic(.light)
                } label: {
                    Text("See all results →")
                        .font(.guideBody(size: 11, weight: .bold))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().stroke(Color.orange.opacity(0.40), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
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
                .fill(Color.white.opacity(0.07))
            )
            Spacer(minLength: 0)
        }
        .id(id)
    }

    private func followUpButton(_ text: String) -> some View {
        Button {
            haptic(.light)
            sendUser(text)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
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
                    .focused($inputFocused)
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

                Button {
                    submitQuery()
                } label: {
                    ZStack {
                        Circle().fill(Color.orange)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                Button(action: submitQuery) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.08))
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
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
            inputFocused = false
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

    private func sendUser(_ text: String) {
        messages.append(.init(isUser: true, text: text, isMatchResult: false))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            messages.append(.init(isUser: false, text: "", isMatchResult: true))
        }
    }

    private func close() {
        haptic(.light)
        inputFocused = false
        onClose()
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

#Preview {
    ZStack {
        Color.navy.ignoresSafeArea()
        AskStreamSheet(isOpen: true, onClose: {})
    }
}
