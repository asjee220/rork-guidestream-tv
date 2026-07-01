//
//  SearchView.swift
//  GuideStreamTV
//
//  Unified search surface with scope chips for All, Live, Shows, Creators, Podcasts.
//  Results are grouped into three sections: Live now, Shows & movies, Creators & podcasts.
//

import SwiftUI

// MARK: - Search result model

struct SearchResult: Identifiable {
    let id: Int // TMDB id
    let title: String
    let isTV: Bool
    let posterUrl: String?
    let backdropUrl: String?
    let year: Int?
    let genreNames: [String]
    let serviceName: String?
    let serviceColor: Color
    let serviceShort: String
}

/// Unified search scope.
enum SearchScope: String, CaseIterable {
    case all, live, shows, creators, podcasts

    var label: String {
        switch self {
        case .all: return "All"
        case .live: return "Live"
        case .shows: return "Shows"
        case .creators: return "Creators"
        case .podcasts: return "Podcasts"
        }
    }
}

// MARK: - Combined search result

struct UnifiedSearchResult: Identifiable {
    let id: String
    let kind: UnifiedResultKind
}

enum UnifiedResultKind {
    case liveCreator(DiscoverableCreator)
    case tmdbShow(SearchResult)
    case creator(DiscoverableCreator)
}

// MARK: - ViewModel

@Observable
final class SearchViewModel {
    var query: String = ""
    var scope: SearchScope = .all
    var isSearching: Bool = false
    var tmdbResults: [SearchResult] = []
    var creatorResults: [DiscoverableCreator] = []
    var popular: [SearchResult] = []
    var error: String? = nil
    var isLoadingCreators: Bool = false

    private var searchTask: Task<Void, Never>?

    func onQueryChange(_ q: String) {
        searchTask?.cancel()
        if q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tmdbResults = []; creatorResults = []; isSearching = false; return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await search(q)
        }
    }

    func loadPopular() async {
        guard popular.isEmpty else { return }
        do {
            let tv = try await TMDBService.shared.getTrending(mediaType: "tv", timeWindow: "week")
            let movies = try await TMDBService.shared.getTrending(mediaType: "movie", timeWindow: "week")
            let combined = (tv + movies).prefix(18)
            let resolved = await withTaskGroup(of: SearchResult?.self) { group in
                for item in combined {
                    group.addTask {
                        let provider = try? await TMDBService.shared.getTopWatchProvider(tmdbId: item.id, isTV: item.isTV)
                        let svcName = provider?.providerName
                        let color = gsBrandColor(for: svcName ?? "")
                        let short = gsShortName(for: svcName ?? "")
                        guard svcName != nil else { return nil }
                        return SearchResult(
                            id: item.id, title: item.displayName, isTV: item.isTV,
                            posterUrl: item.posterUrl, backdropUrl: item.backdropUrl,
                            year: item.year, genreNames: [],
                            serviceName: svcName, serviceColor: color, serviceShort: short
                        )
                    }
                }
                var out: [SearchResult] = []
                for await r in group { if let r { out.append(r) } }
                return out
            }
            await MainActor.run { self.popular = resolved }
        } catch {}
    }

    @MainActor
    private func search(_ q: String) async {
        isSearching = true
        defer { isSearching = false }

        let includeTMDB = scope == .all || scope == .shows || scope == .live
        let includeCreators = scope == .all || scope == .creators || scope == .podcasts || scope == .live

        async let tmdb: () = includeTMDB ? fetchTMDB(q) : { await MainActor.run { tmdbResults = [] } }()
        async let creators: () = includeCreators ? fetchCreators(q) : { await MainActor.run { creatorResults = [] } }()

        _ = await (tmdb, creators)
    }

    private func fetchTMDB(_ q: String) async {
        do {
            let raw = try await TMDBService.shared.search(query: q)
            await MainActor.run {
                tmdbResults = raw.compactMap { item in
                    SearchResult(
                        id: item.id, title: item.displayName, isTV: item.isTV,
                        posterUrl: item.posterUrl, backdropUrl: item.backdropUrl,
                        year: item.year, genreNames: [],
                        serviceName: nil, serviceColor: Color(white: 0.18), serviceShort: "")
                }
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func fetchCreators(_ q: String) async {
        await MainActor.run { isLoadingCreators = true }
        defer { Task { @MainActor in isLoadingCreators = false } }
        do {
            let st: String? = {
                switch scope {
                case .podcasts: return "podcast"
                case .creators: return nil // youtube + twitch + kick
                default: return nil
                }
            }()
            let localSources = try await ContentSourcesService.shared.searchSources(query: q, sourceType: st)

            // Live search across YouTube + Twitch via the backend worker.
            // Skip for the podcasts scope (no live podcast search backend).
            let liveType: String? = {
                switch scope {
                case .podcasts: return "podcast"
                case .creators, .all, .live: return "all"
                default: return "all"
                }
            }()
            var liveSources: [ContentSource] = []
            if let lt = liveType {
                liveSources = await ContentSourcesService.shared.searchCreatorsLive(query: q, type: lt)
            }

            // Merge: local DB rows take precedence, live results fill the gaps.
            // Also drop live rows whose display_name collides with a local row
            // (case-insensitive, trimmed) even when title_id differs — prevents
            // iTunes podcast results from duplicating seed podcasts.
            let localNames = Set(localSources.map { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            var mergedById: [String: ContentSource] = [:]
            for s in liveSources {
                let liveName = s.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if localNames.contains(liveName) { continue }
                mergedById[s.titleId] = s
            }
            for s in localSources { mergedById[s.titleId] = s }
            let sources = Array(mergedById.values)

            // Filter client-side for scope
            let filtered: [ContentSource] = {
                if scope == .creators {
                    return sources.filter { SourceKind.from(titleId: $0.titleId) != .podcast }
                }
                if scope == .podcasts {
                    return sources.filter { SourceKind.from(titleId: $0.titleId) == .podcast }
                }
                return sources
            }()
            let liveIds = filtered.filter { SourceKind.from(titleId: $0.titleId).isLivestream }.map { $0.titleId }
            let liveMap: [String: LiveStatus] = liveIds.isEmpty ? [:] : Dictionary(
                uniqueKeysWithValues: (try? await ContentSourcesService.shared.fetchLiveStatus(for: liveIds))?.map { ($0.titleId, $0) } ?? []
            )
            await MainActor.run {
                creatorResults = filtered.map { source in
                    let status = liveMap[source.titleId]
                    return DiscoverableCreator(
                        titleId: source.titleId, sourceType: source.sourceType,
                        displayName: source.displayName, handle: source.handle,
                        imageUrl: source.imageUrl, category: source.category,
                        description: source.description,
                        format: source.format,
                        isLive: status?.isLive ?? false, streamTitle: status?.streamTitle,
                        liveCategory: status?.category, viewerCount: status?.viewerCount,
                        startedAt: status?.startedAt
                    )
                }
                // Sort: live first
                creatorResults.sort { a, b in
                    if a.isLive != b.isLive { return a.isLive }
                    return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
                }
            }
        } catch {
            await MainActor.run { creatorResults = [] }
        }
    }

    /// Grouped results for rendering.
    var liveCreators: [DiscoverableCreator] {
        creatorResults.filter { $0.isLive }
    }

    var nonLiveCreators: [DiscoverableCreator] {
        creatorResults.filter { !$0.isLive }
    }
}

// MARK: - SearchView

struct SearchView: View {
    @Binding var isPresented: Bool
    var onSelectResult: ((SearchResult) -> Void)? = nil
    var onCreatorSelect: ((DiscoverableCreator) -> Void)? = nil

    @State private var vm = SearchViewModel()
    @State private var followedIds: Set<String> = []
    @State private var streams = StreamsViewModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            BrandBackground()

            VStack(spacing: 0) {
                // Search bar row
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.orange)
                        TextField("Search shows, creators, podcasts…", text: $vm.query)
                            .focused($focused)
                            .foregroundStyle(.white)
                            .tint(Color.orange)
                            .font(.system(size: 15))
                            .autocorrectionDisabled()
                            .onChange(of: vm.query) { _, q in vm.onQueryChange(q) }
                        if !vm.query.isEmpty {
                            Button {
                                vm.query = ""
                                vm.tmdbResults = []
                                vm.creatorResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(focused ? Color.orange.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Button("Cancel") {
                        focused = false
                        isPresented = false
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.orange)
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                .padding(.bottom, 6)

                // Scope chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SearchScope.allCases, id: \.rawValue) { scope in
                            Button {
                                focused = false
                                withAnimation(.easeOut(duration: 0.2)) {
                                    vm.scope = scope
                                }
                                if !vm.query.isEmpty {
                                    vm.onQueryChange(vm.query)
                                }
                            } label: {
                                Text(scope.label)
                                    .scaledFont(size: 12, weight: .semibold)
                                    .foregroundStyle(vm.scope == scope ? .white : Color.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(vm.scope == scope ? Color.orange : Color.white.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }

                Divider().overlay(Color.white.opacity(0.07))

                // Content area
                ScrollView(showsIndicators: false) {
                    if vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        popularGrid
                    } else if vm.isSearching {
                        HStack { Spacer(); ProgressView().tint(Color.orange); Spacer() }
                            .padding(.top, 40)
                    } else {
                        searchResults
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            focused = true
            syncFollowed()
            Task { await vm.loadPopular() }
        }

    }

    // MARK: - Followed sync

    private func syncFollowed() {
        followedIds = Set(streams.userStreams.map { $0.titleId })
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResults: some View {
        let hasLive = !vm.liveCreators.isEmpty
        let hasShows = !vm.tmdbResults.isEmpty
        let hasCreators = !vm.nonLiveCreators.isEmpty

        if !hasLive && !hasShows && !hasCreators {
            Text("No results for \"\(vm.query)\"")
                .scaledFont(size: 13)
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // 1. Live now section
                if hasLive {
                    sectionHeader("LIVE NOW")
                    ForEach(vm.liveCreators) { creator in
                        CreatorSearchRow(creator: creator, isFollowed: followedIds.contains(creator.titleId)) {
                            toggleFollow(creator)
                        } onTap: {
                            openCreator(creator)
                        }
                    }
                }

                // 2. Shows & movies section
                if hasShows {
                    sectionHeader("SHOWS & MOVIES")
                    ForEach(Array(vm.tmdbResults.enumerated()), id: \.element.id) { idx, result in
                        TypeAheadRow(result: result, query: vm.query) { openTMDB(result) }
                        if idx < vm.tmdbResults.count - 1 {
                            Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 130)
                        }
                    }
                }

                // 3. Creators & podcasts section
                if hasCreators {
                    sectionHeader("CREATORS & PODCASTS")
                    ForEach(vm.nonLiveCreators) { creator in
                        CreatorSearchRow(creator: creator, isFollowed: followedIds.contains(creator.titleId)) {
                            toggleFollow(creator)
                        } onTap: {
                            openCreator(creator)
                        }
                    }
                }
            }
        }
        Color.clear.frame(height: 100)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 11, weight: .bold)
            .foregroundStyle(Color.white.opacity(0.4))
            .tracking(0.8)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func toggleFollow(_ creator: DiscoverableCreator) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if followedIds.contains(creator.titleId) {
            followedIds.remove(creator.titleId)
            Task {
                await streams.removeFromMyStreams(titleId: creator.titleId)
                WatchIntentLogger.shared.log(eventType: .streamRemoved, titleId: creator.titleId, platformId: creator.sourceType, metadata: ["source": "search"])
            }
        } else {
            followedIds.insert(creator.titleId)
            Task {
                await streams.addToMyStreams(titleId: creator.titleId, title: creator.displayName, posterUrl: creator.imageUrl, platform: creator.sourceType)
                WatchIntentLogger.shared.log(eventType: .streamAdded, titleId: creator.titleId, platformId: creator.sourceType, metadata: ["source": "search"])
            }
        }
    }

    private func openCreator(_ creator: DiscoverableCreator) {
        WatchIntentLogger.shared.log(eventType: .cardTapped, titleId: creator.titleId, platformId: creator.sourceType, metadata: ["section": "search", "kind": creator.sourceType])
        if let cb = onCreatorSelect { cb(creator); return }
        isPresented = false
    }

    private func openTMDB(_ result: SearchResult) {
        if let cb = onSelectResult { cb(result); return }
        isPresented = false
    }

    // MARK: - Popular grid

    private var popularGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("POPULAR ON YOUR SERVICES")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.4))
                .tracking(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if vm.popular.isEmpty {
                HStack { Spacer(); ProgressView().tint(Color.orange); Spacer() }
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(vm.popular) { result in
                        PosterCell(result: result) { openTMDB(result) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 100)
            }
        }
    }
}

// MARK: - Creator Search Row

private struct CreatorSearchRow: View {
    let creator: DiscoverableCreator
    let isFollowed: Bool
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(sourceColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    if let url = CreatorImageOverrides.resolve(titleId: creator.titleId, stored: creator.avatarUrl) {
                        RemoteImage(urlString: url, contentMode: .fill, fallbackColors: [sourceColor, sourceColor.opacity(0.5)])
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .allowsHitTesting(false)
                    } else {
                        Image(systemName: creator.kind == .podcast ? "mic.fill" : "play.rectangle.fill")
                            .scaledFont(size: 18, weight: .semibold)
                            .foregroundStyle(sourceColor)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(creator.displayName)
                            .scaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if creator.isLive { LivePill() }
                    }
                    HStack(spacing: 6) {
                        SourceTypeBadge(kind: creator.kind, format: creator.format)
                        if let handle = creator.handle {
                            let cleanHandle = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
                            Text("@\(cleanHandle)")
                                .scaledFont(size: 12)
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    if creator.isLive, let title = creator.streamTitle {
                        Text(title)
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Button(action: onToggle) {
                    Text(isFollowed ? "Following" : "Follow")
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(isFollowed ? Color.textSecondary : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(isFollowed ? Color.white.opacity(0.10) : Color.orange))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sourceColor: Color {
        switch creator.kind {
        case .youtube: return Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255)
        case .podcast: return Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255)
        case .twitch: return Color(red: 0x91/255, green: 0x46/255, blue: 0xFF/255)
        case .kick: return Color(red: 0x53/255, green: 0xFC/255, blue: 0x18/255)
        case .tmdb: return Color.orange
        }
    }
}

// MARK: - Legacy sub-views

private struct PosterCell: View {
    let result: SearchResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(2/3, contentMode: .fit)
                    .overlay {
                        if let url = result.posterUrl.flatMap(URL.init) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().aspectRatio(contentMode: .fill)
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.9)],
                    startPoint: .center, endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)

                if result.serviceName != nil {
                    Text(result.serviceShort)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(result.serviceColor))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct TypeAheadRow: View {
    let result: SearchResult
    let query: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 100, height: 150)
                    .overlay {
                        if let url = result.posterUrl.flatMap(URL.init) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().aspectRatio(contentMode: .fill)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    highlightedTitle
                    Text(result.isTV ? "TV Series" : "Movie")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.4))
                    if let year = result.year {
                        Text(String(year))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let svc = result.serviceName {
                    Text(result.serviceShort)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(result.serviceColor))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.2))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var highlightedTitle: some View {
        let lower = result.title.lowercased()
        let qLower = query.lowercased()
        if let range = lower.range(of: qLower) {
            let start = result.title[result.title.startIndex..<range.lowerBound]
            let match = result.title[range]
            let end = result.title[range.upperBound...]
            Group {
                Text(String(start)).foregroundStyle(.white) +
                Text(String(match)).foregroundStyle(Color.orange) +
                Text(String(end)).foregroundStyle(.white)
            }
            .font(.system(size: 15, weight: .semibold))
        } else {
            Text(result.title)
                .foregroundStyle(.white)
                .font(.system(size: 15, weight: .semibold))
        }
    }
}
