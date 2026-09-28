//
//  MacPages.swift
//  GuideStreamTVMac
//
//  Search, Watchlist, Sports, Profile and the Ask sheet. Each reads the
//  same services the Apple TV app uses.
//

import SwiftUI

// MARK: - Search

struct MacSearchView: View {
    @State private var query = ""
    @State private var results: [TVTMDBResult] = []
    @State private var searching = false
    @FocusState private var focused: Bool
    @Environment(\.openTitle) private var openTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.white.opacity(0.4))
                TextField("Search shows, movies and creators", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                if searching { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MacColor.hairline, lineWidth: 1))

            if results.isEmpty {
                Text(query.isEmpty ? "Type a title to see where it's streaming." : (searching ? "" : "No matches for \u{201C}\(query)\u{201D}."))
                    .font(.system(size: 13))
                    .foregroundStyle(MacColor.text2)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: MacLayout.posterWidth), spacing: 14)],
                              alignment: .leading, spacing: 18) {
                        ForEach(results) { r in
                            MacPosterCard(title: r.displayName,
                                          subtitle: [r.isTV ? "Series" : "Movie", r.year.map(String.init)].compactMap { $0 }.joined(separator: " · "),
                                          posterUrl: r.posterUrl) { openTitle(MacTitleRef(result: r)) }
                        }
                    }
                }
            }
        }
        .padding(MacLayout.contentPadding)
        .onAppear { focused = true }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count >= 2 else { results = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            results = ((try? await TVTMDBService.shared.searchContent(query: q)) ?? [])
                .filter { $0.posterPath != nil }
            WatchIntentLogger.shared.log(eventType: .searchQuery, metadata: ["query": q, "results": results.count, "surface": "mac"])
        }
    }
}

// MARK: - Watchlist

struct MacWatchlistView: View {
    enum Filter: String, CaseIterable { case all = "All", shows = "Shows", movies = "Movies", creators = "Creators" }
    @State private var streams = TVStreamsViewModel.shared
    @State private var filter: Filter = .all
    @Environment(\.openTitle) private var openTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !AuthViewModel.shared.isAuthenticated {
                MacEmptyState(icon: "bookmark", title: "Sign in to see your watchlist",
                              message: "Your watchlist syncs with GuideStream on iPhone and Apple TV.")
            } else {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                .labelsHidden()

                if rows.isEmpty {
                    MacEmptyState(icon: "bookmark", title: "Nothing here yet",
                                  message: "Add shows, movies and creators from any title page.")
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: MacLayout.posterWidth), spacing: 14)],
                                  alignment: .leading, spacing: 18) {
                            ForEach(rows) { row in
                                let p = Platform.from(providerName: row.platform)
                                MacPosterCard(title: row.title ?? "Untitled", subtitle: kindLabel(row),
                                              posterUrl: streams.displayPosterUrl(for: row),
                                              badge: p.map { .tag($0.name, $0.color) } ?? .none) { open(row) }
                            }
                        }
                    }
                }
            }
        }
        .padding(MacLayout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await streams.fetchUserStreams() }
    }

    private var rows: [TVUserStream] {
        streams.userStreams.filter { row in
            let media = TVTitleID.mediaType(from: row.titleId)
            switch filter {
            case .all: return true
            case .shows: return media == "tv"
            case .movies: return media == "movie"
            case .creators: return TVCreatorKind.from(titleId: row.titleId) != nil
            }
        }
    }

    private func kindLabel(_ row: TVUserStream) -> String {
        if let kind = TVCreatorKind.from(titleId: row.titleId) { return kind.displayLabel }
        return TVTitleID.mediaType(from: row.titleId) == "movie" ? "Movie" : "Series"
    }

    private func open(_ row: TVUserStream) {
        if let id = TVTitleID.tmdbId(from: row.titleId) {
            openTitle(MacTitleRef(titleId: row.titleId, tmdbId: id,
                                  isTV: TVTitleID.mediaType(from: row.titleId) != "movie",
                                  title: row.title ?? "", posterUrl: streams.displayPosterUrl(for: row)))
        } else if let url = MacCreatorLinks.url(for: row.titleId) {
            MacLinkOpener.open(url)
        }
    }
}

// MARK: - Sports

struct MacSportsView: View {
    @State private var games: [TVSportsGame] = []
    @State private var league = "All"
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(leagues, id: \.self) { l in
                        Button { league = l } label: {
                            Text(l)
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 16).padding(.vertical, 6)
                                .foregroundStyle(league == l ? .white : MacColor.text2)
                                .background(league == l ? MacColor.orange : .clear, in: Capsule())
                                .overlay(Capsule().stroke(league == l ? MacColor.orange : MacColor.hairline, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity)
                Spacer()
            } else if filtered.isEmpty {
                MacEmptyState(icon: "sportscourt", title: "No games right now", message: "Check back closer to game time.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(filtered) { MacGameCard(game: $0) }
                    }
                }
            }
        }
        .padding(MacLayout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            games = await TVSportsService.shared.fetchAll()
            loading = false
        }
    }

    private var leagues: [String] {
        var seen = Set<String>()
        return ["All"] + games.map(\.sport).filter { seen.insert($0).inserted }
    }

    private var filtered: [TVSportsGame] {
        let list = league == "All" ? games : games.filter { $0.sport == league }
        return list.sorted { a, b in
            if a.state.isLive != b.state.isLive { return a.state.isLive }
            return (a.startDate ?? .distantFuture) < (b.startDate ?? .distantFuture)
        }
    }
}

private struct MacGameCard: View {
    let game: TVSportsGame

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                crest(game.away)
                Text("vs").font(.system(size: 12)).foregroundStyle(MacColor.text3)
                crest(game.home)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(game.away.shortName) vs \(game.home.shortName)").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(status).font(.system(size: 12)).foregroundStyle(game.state.isLive ? MacColor.live : MacColor.text3)
                }
                Spacer()
                if game.state != .pre {
                    Text("\(game.away.score)–\(game.home.score)").font(.system(size: 15, weight: .bold)).monospacedDigit()
                }
            }
            if !game.broadcasts.isEmpty {
                HStack(spacing: 6) {
                    Text("ON:").font(.system(size: 11)).foregroundStyle(MacColor.text3)
                    ForEach(game.broadcasts.prefix(4), id: \.self) { b in
                        Text(b).font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color(red: 0.07, green: 0.19, blue: 0.37), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
        .padding(14)
        .background(MacColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(MacColor.hairline, lineWidth: 1))
    }

    private var status: String {
        let league = game.leagueShort.isEmpty ? game.sport : game.leagueShort
        if game.state == .pre, let d = game.startDate {
            let f = DateFormatter()
            f.dateFormat = Calendar.current.isDateInToday(d) ? "h:mm a" : "EEE h:mm a"
            return "\(league) · \(f.string(from: d))"
        }
        return "\(league) · \(game.statusDetail)"
    }

    private func crest(_ team: TVGameTeam) -> some View {
        ZStack {
            Circle().fill(Color.fromHex(team.primaryHex) ?? MacColor.elevated)
            if let logo = team.logoURL {
                TVRemoteImage(urlString: logo, contentMode: .fit).padding(6)
            } else {
                Text(team.abbreviation).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 36, height: 36)
    }
}

// MARK: - Profile

struct MacProfileView: View {
    @State private var auth = AuthViewModel.shared
    @State private var selected: Set<String> = []
    @State private var filter = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [MacColor.blue, Color(red: 0.36, green: 0.69, blue: 1)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text(auth.initials).font(.system(size: 20, weight: .bold))
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(auth.displayName ?? (auth.isGuest ? "Guest" : "Your account")).font(.system(size: 20, weight: .bold))
                        Text(auth.currentUser?.email ?? "Browsing as a guest").font(.system(size: 13)).foregroundStyle(MacColor.text2)
                    }
                    Spacer()
                    Button(auth.isAuthenticated ? "Sign out" : "Sign in") {
                        Task { await auth.signOut() }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Your services").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 180)
                        Button("Save") { auth.setSelectedServices(selected) }
                            .keyboardShortcut("s")
                            .disabled(selected == auth.selectedServices)
                    }
                    Text("Home ranks and labels titles by the services you pick. Changes sync to your other devices.")
                        .font(.system(size: 12)).foregroundStyle(MacColor.text2)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(catalog) { s in
                            let on = selected.contains(s.id)
                            Button {
                                if on { selected.remove(s.id) } else { selected.insert(s.id) }
                            } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(s.color).frame(width: 10, height: 10)
                                    Text(s.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Spacer()
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(on ? MacColor.orange : MacColor.text3)
                                }
                                .padding(10)
                                .background(on ? MacColor.orange.opacity(0.12) : MacColor.surface, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? MacColor.orange.opacity(0.5) : MacColor.hairline, lineWidth: 1))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("GuideStream TV for Mac \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.system(size: 11)).foregroundStyle(MacColor.text3)
            }
            .padding(MacLayout.contentPadding)
        }
        .onAppear { selected = auth.selectedServices }
    }

    /// Selected services first, then the rest of the phone's catalogue.
    private var catalog: [StreamingService] {
        let all = StreamingCatalog.all.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
        return all.filter { auth.selectedServices.contains($0.id) } + all.filter { !auth.selectedServices.contains($0.id) }
    }
}

// MARK: - Ask

struct MacAskSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(MacColor.orange)
            Text("Ask GuideStream").font(.system(size: 20, weight: .bold))
            Text("AskStream comes to Mac in the next build. On iPhone, tap the orange Ask button to try it now.")
                .font(.system(size: 13)).foregroundStyle(MacColor.text2)
                .multilineTextAlignment(.center)
                .frame(width: 340)
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(32)
        .background(MacColor.navy)
    }
}

// MARK: - Empty state

struct MacEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(MacColor.text3)
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(message).font(.system(size: 13)).foregroundStyle(MacColor.text2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
