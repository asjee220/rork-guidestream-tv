//
//  MacSearchView.swift
//  GuideStreamTVMac
//
//  Search, matching the phone's SearchView: All / Live / Shows / Creators /
//  Podcasts scopes; before typing, Browse by genre and Popular on your
//  services; while typing, Live now, Shows & movies (TMDB) and Creators
//  (content_sources plus the `search_creators` edge function, as on iOS).
//  A genre opens the browse grid (TVTMDBService.discoverBrowse), with the
//  same type, sort and "my services" filters as the phone.
//

import SwiftUI
import Supabase

enum MacSearchScope: String, CaseIterable, Identifiable {
    case all, live, shows, creators, podcasts
    var id: String { rawValue }
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

struct MacFoundCreator: Identifiable, Hashable {
    let source: TVCreatorSource
    let live: TVLiveStatus?
    var id: String { source.titleId }
    var isLive: Bool { live?.isLive ?? false }
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor
@Observable
final class MacSearchModel {
    static let shared = MacSearchModel()
    private init() {}

    var query = ""
    var scope: MacSearchScope = .all
    var isSearching = false
    var titles: [TVTMDBResult] = []
    var creators: [MacFoundCreator] = []
    var popular: [(TVTMDBResult, String?)] = []

    private var client: SupabaseClient { TVSupabaseManager.shared.client }

    func loadPopular() async {
        guard popular.isEmpty else { return }
        let trending = Array(((try? await TVTMDBService.shared.getTrending()) ?? []).prefix(18))
        let resolved = await withTaskGroup(of: (Int, TVTMDBResult, String?).self) { group in
            for (i, item) in trending.enumerated() {
                group.addTask {
                    let p = try? await TVTMDBService.shared.getTopWatchProvider(tmdbId: item.id, isTV: item.isTV)
                    return (i, item, p?.providerName)
                }
            }
            var out: [(Int, TVTMDBResult, String?)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }
        }
        // Services the viewer has come first, as the section title promises.
        let mine = resolved.filter { $0.2.map { AuthViewModel.shared.subscribesToService(named: $0) } ?? false }
        let rest = resolved.filter { !($0.2.map { AuthViewModel.shared.subscribesToService(named: $0) } ?? false) }
        popular = (mine + rest).map { ($0.1, $0.2) }
    }

    func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { titles = []; creators = []; return }
        isSearching = true
        defer { isSearching = false }
        let wantTitles = scope == .all || scope == .shows || scope == .live
        let wantCreators = scope != .shows
        async let t: [TVTMDBResult] = wantTitles ? ((try? await TVTMDBService.shared.searchContent(query: q)) ?? []) : []
        async let c: [MacFoundCreator] = wantCreators ? searchCreators(q) : []
        let (tt, cc) = await (t, c)
        guard q == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        titles = scope == .live ? [] : tt.filter { $0.posterPath != nil }
        creators = scope == .live ? cc.filter(\.isLive) : cc
    }

    private struct LiveSearch: Decodable { let ok: Bool; let results: [TVCreatorSource] }

    private func searchCreators(_ q: String) async -> [MacFoundCreator] {
        // Local catalogue first (content_sources), then the live directory
        // search; local rows win on a name clash, as on iOS.
        var local: [TVCreatorSource] = []
        do {
            var db = client.from("content_sources").select().ilike("display_name", pattern: "%\(q)%")
            db = scope == .podcasts ? db.eq("source_type", value: "podcast")
                                    : db.in("source_type", values: TVCreatorKind.sourceTypes)
            local = try await db.order("created_at", ascending: false).limit(30).execute().value
        } catch {}
        var remote: [TVCreatorSource] = []
        if let r: LiveSearch = try? await client.functions.invoke(
            "search_creators", options: FunctionInvokeOptions(body: ["q": q, "type": scope == .podcasts ? "podcast" : "all"])
        ), r.ok {
            remote = r.results
        }
        let localNames = Set(local.map { $0.displayName.lowercased() })
        var merged: [String: TVCreatorSource] = [:]
        for s in remote where !localNames.contains(s.displayName.lowercased()) { merged[s.titleId] = s }
        for s in local { merged[s.titleId] = s }
        var sources = Array(merged.values)
        if scope == .creators { sources = sources.filter { TVCreatorKind.from(titleId: $0.titleId) != .podcast } }
        if scope == .podcasts { sources = sources.filter { TVCreatorKind.from(titleId: $0.titleId) == .podcast } }

        let liveIds = sources.map(\.titleId).filter { TVCreatorKind.from(titleId: $0)?.isLivestream == true }
        var liveMap: [String: TVLiveStatus] = [:]
        if !liveIds.isEmpty, let rows: [TVLiveStatus] = try? await client.from("live_status").select()
            .in("title_id", values: liveIds).execute().value {
            for r in rows { liveMap[r.titleId] = r }
        }
        return sources.map { MacFoundCreator(source: $0, live: liveMap[$0.titleId]) }
            .sorted { a, b in a.isLive != b.isLive ? a.isLive : a.source.displayName.localizedStandardCompare(b.source.displayName) == .orderedAscending }
    }
}

struct MacSearchView: View {
    @State private var model = MacSearchModel.shared
    @State private var streams = TVStreamsViewModel.shared
    @State private var browseGenre: BrowseGenre?
    @State private var artwork = TVBrowseArtworkStore.shared
    @FocusState private var focused: Bool
    @Environment(\.openTitle) private var openTitle
    @Environment(\.openCreator) private var openCreator

    var body: some View {
        if let genre = browseGenre {
            MacBrowseResultsView(genre: genre) { browseGenre = nil }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(MacColor.orange)
                    TextField("Search shows, creators, podcasts…", text: $model.query)
                        .textFieldStyle(.plain).font(.system(size: 15)).focused($focused)
                    if model.isSearching { ProgressView().controlSize(.small) }
                    if !model.query.isEmpty {
                        Button("Clear") { model.query = "" }.buttonStyle(.plain).foregroundStyle(MacColor.orange)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(focused ? MacColor.orange.opacity(0.6) : MacColor.hairline, lineWidth: 1))

                HStack(spacing: 8) {
                    ForEach(MacSearchScope.allCases) { s in
                        Button { model.scope = s } label: {
                            Text(s.label).font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .foregroundStyle(model.scope == s ? .white : MacColor.text2)
                                .background(model.scope == s ? MacColor.orange : Color.white.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if model.query.trimmingCharacters(in: .whitespaces).isEmpty { idle } else { results }
                    }
                    .padding(.bottom, 20)
                }
            }
            .padding(MacLayout.contentPadding)
            .onAppear { focused = true }
            .task { await model.loadPopular(); await artwork.loadIfNeeded() }
            .task(id: "\(model.query)|\(model.scope.rawValue)") {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await model.search()
                try? await Task.sleep(for: .milliseconds(1250))
                guard !Task.isCancelled, model.query.count >= 3 else { return }
                WatchIntentLogger.shared.log(eventType: .searchQuery, metadata: [
                    "query": model.query, "surface": "search", "scope": model.scope.rawValue,
                    "result_count": model.titles.count + model.creators.count])
            }
        }
    }

    // MARK: Idle — browse by genre + popular

    @ViewBuilder private var idle: some View {
        sectionHeader("BROWSE BY GENRE")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
            ForEach(BrowseCatalog.genres) { g in
                Button { browseGenre = g } label: { genreTile(g) }.buttonStyle(.plain)
            }
        }
        if !model.popular.isEmpty {
            sectionHeader("POPULAR ON YOUR SERVICES")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: MacLayout.posterWidth), spacing: 14)], alignment: .leading, spacing: 18) {
                ForEach(model.popular, id: \.0.id) { item, provider in
                    let p = provider.flatMap { Platform.from(providerName: $0) }
                    MacPosterCard(title: item.displayName, posterUrl: item.posterUrl,
                                  badge: p.map { .tag($0.displayName, $0.color) } ?? .none) { openTitle(MacTitleRef(result: item)) }
                }
            }
        }
    }

    private func genreTile(_ g: BrowseGenre) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: TVGenreTint.colors(for: g.id), startPoint: .topLeading, endPoint: .bottomTrailing)
            if let url = artwork.backdrops[g.id] {
                TVRemoteImage(urlString: url, contentMode: .fill).frame(height: 120).clipped()
            }
            LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .bottom, endPoint: .center)
            Text(g.name).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 10).padding(14)
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MacColor.hairline, lineWidth: 1))
        .contentShape(Rectangle())
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        let live = model.creators.filter(\.isLive)
        let others = model.creators.filter { !$0.isLive }
        if model.titles.isEmpty && model.creators.isEmpty && !model.isSearching {
            Text("No results for \u{201C}\(model.query)\u{201D}").font(.system(size: 14)).foregroundStyle(MacColor.text2)
        }
        if !live.isEmpty {
            sectionHeader("LIVE NOW")
            creatorList(live)
        }
        if !model.titles.isEmpty {
            sectionHeader("SHOWS & MOVIES")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: MacLayout.posterWidth), spacing: 14)], alignment: .leading, spacing: 18) {
                ForEach(model.titles) { r in
                    MacPosterCard(title: r.displayName,
                                  subtitle: [r.isTV ? "Series" : "Movie", r.year.map(String.init)].compactMap { $0 }.joined(separator: " · "),
                                  posterUrl: r.posterUrl) { openTitle(MacTitleRef(result: r)) }
                }
            }
        }
        if !others.isEmpty {
            sectionHeader(model.scope == .podcasts ? "PODCASTS" : "CREATORS & PODCASTS")
            creatorList(others)
        }
    }

    private func creatorList(_ list: [MacFoundCreator]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(list) { c in creatorRow(c) }
        }
    }

    private func creatorRow(_ c: MacFoundCreator) -> some View {
        let kind = TVCreatorKind.from(titleId: c.source.titleId)
        let following = streams.contains(titleId: c.source.titleId)
        return HStack(spacing: 12) {
            Button { openCreator(c.source.titleId) } label: {
                HStack(spacing: 12) {
                    TVRemoteImage(urlString: c.source.imageUrl, contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(kind == .podcast ? AnyShape(RoundedRectangle(cornerRadius: 10)) : AnyShape(Circle()))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(c.source.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            if c.isLive {
                                Text("LIVE").font(.system(size: 9, weight: .heavy)).padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(MacColor.live, in: Capsule())
                            }
                        }
                        Text(c.isLive ? (c.live?.streamTitle ?? kind?.displayLabel ?? "") :
                                [kind?.displayLabel, c.source.handle.map { "@\($0.trimmingCharacters(in: CharacterSet(charactersIn: "@")))" }]
                                    .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(MacColor.text2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                Task {
                    if following {
                        await streams.remove(titleId: c.source.titleId)
                    } else {
                        await streams.add(titleId: c.source.titleId, title: c.source.displayName,
                                          posterUrl: c.source.imageUrl, platform: c.source.sourceType)
                    }
                }
            } label: {
                Text(following ? "Following" : "Follow").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(following ? MacColor.text2 : .white)
                    .background(following ? Color.white.opacity(0.08) : MacColor.orange, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!AuthViewModel.shared.isAuthenticated)
        }
        .padding(10)
        .background(MacColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MacColor.hairline, lineWidth: 1))
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .bold)).tracking(1.4).foregroundStyle(MacColor.text3)
    }
}

// MARK: - Browse results (genre)

struct MacBrowseResultsView: View {
    let genre: BrowseGenre
    let onBack: () -> Void
    @State private var filters: BrowseFilters
    @State private var results: [TVTMDBResult] = []
    @State private var page = 1
    @State private var totalPages = 1
    @State private var totalResults = 0
    @State private var loading = true
    @State private var paging = false
    @Environment(\.openTitle) private var openTitle

    init(genre: BrowseGenre, onBack: @escaping () -> Void) {
        self.genre = genre
        self.onBack = onBack
        let ids = AuthViewModel.shared.selectedServices.compactMap { MacHomeModel.tmdbProviderIdMap[$0] }
        _filters = State(initialValue: BrowseFilters(genreIds: [genre.id], onlyMyServices: !ids.isEmpty, providerIds: ids))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button(action: onBack) { Label("Search", systemImage: "chevron.left") }.buttonStyle(.bordered)
                Text(genre.name).font(.system(size: 22, weight: .bold))
                Text(loading ? "" : "\(totalResults.formatted()) titles").font(.system(size: 13)).foregroundStyle(MacColor.text3)
                Spacer()
            }
            HStack(spacing: 10) {
                Picker("Type", selection: $filters.mediaType) {
                    ForEach(BrowseMediaType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 240)
                Picker("Sort", selection: $filters.sort) {
                    ForEach(BrowseSort.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .frame(width: 200)
                Toggle("Only my services", isOn: $filters.onlyMyServices)
                    .toggleStyle(.switch)
                    .disabled(filters.providerIds.isEmpty)
                Spacer()
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                MacEmptyState(icon: "film.stack", title: "Nothing matches these filters",
                              message: filters.onlyMyServices ? "Turn off \u{201C}Only my services\u{201D} to see everything." : "Try another type or sort.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: MacLayout.posterWidth), spacing: 14)], alignment: .leading, spacing: 18) {
                        ForEach(results) { r in
                            MacPosterCard(title: r.displayName,
                                          subtitle: [r.isTV ? "Series" : "Movie", r.year.map(String.init)].compactMap { $0 }.joined(separator: " · "),
                                          posterUrl: r.posterUrl, badge: .rating(r.voteAverage)) { openTitle(MacTitleRef(result: r)) }
                                .onAppear { if r.id == results.last?.id { Task { await pageIn() } } }
                        }
                    }
                    if paging { ProgressView().frame(maxWidth: .infinity).padding() }
                }
            }
        }
        .padding(MacLayout.contentPadding)
        .task(id: filters.signature) { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        guard let p = try? await TVTMDBService.shared.discoverBrowse(filters, page: 1) else { results = []; return }
        results = p.results
        page = p.page
        totalPages = p.totalPages
        totalResults = p.totalResults
    }

    private func pageIn() async {
        guard !paging, page < totalPages else { return }
        paging = true
        defer { paging = false }
        let snapshot = filters
        guard let p = try? await TVTMDBService.shared.discoverBrowse(snapshot, page: page + 1),
              snapshot.signature == filters.signature else { return }
        let seen = Set(results.map(\.id))
        results += p.results.filter { !seen.contains($0.id) }
        page = p.page
    }
}
