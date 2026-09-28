//
//  MacPages.swift
//  GuideStreamTVMac
//
//  Search, Watchlist, Sports, Profile and the Ask sheet. Each reads the
//  same services the Apple TV app uses.
//

import SwiftUI

// MARK: - Watchlist

struct MacWatchlistView: View {
    enum Filter: String, CaseIterable { case all = "All", shows = "Shows", movies = "Movies", creators = "Creators" }
    @State private var streams = TVStreamsViewModel.shared
    @State private var filter: Filter = .all
    @Environment(\.openTitle) private var openTitle
    @Environment(\.openCreator) private var openCreator

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

    /// "tv" / "movie" for TMDB rows in either id form, nil for creators.
    static func media(_ row: TVUserStream) -> String? {
        if let m = TVTitleID.mediaType(from: row.titleId) { return m }
        guard Int(row.titleId.trimmingCharacters(in: .whitespaces)) != nil else { return nil }
        return row.isTv == false ? "movie" : "tv"
    }

    private var rows: [TVUserStream] {
        streams.userStreams.filter { row in
            let media = Self.media(row)
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
        return Self.media(row) == "movie" ? "Movie" : "Series"
    }

    private func open(_ row: TVUserStream) {
        if let id = TVTitleID.tmdbId(from: row.titleId) {
            let isTV = Self.media(row) != "movie"
            openTitle(MacTitleRef(titleId: "tmdb:\(isTV ? "tv" : "movie"):\(id)", tmdbId: id,
                                  isTV: isTV,
                                  title: row.title ?? "", posterUrl: streams.displayPosterUrl(for: row)))
        } else if TVCreatorKind.from(titleId: row.titleId) != nil {
            openCreator(row.titleId)
        }
    }
}

// MARK: - Sports

struct MacSportsView: View {
    @State private var games: [TVSportsGame] = []
    @State private var league = "All"
    @State private var loading = true
    @Environment(\.openGame) private var openGame

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
                        ForEach(filtered) { g in
                            Button { openGame(g) } label: { MacGameCard(game: g) }.buttonStyle(.plain)
                        }
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
        // Live first, then upcoming soonest-first, then finals newest-first.
        func rank(_ g: TVSportsGame) -> Int { g.state == .live ? 0 : (g.state == .pre ? 1 : 2) }
        return list.sorted { a, b in
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            let da = a.startDate ?? .distantPast, db = b.startDate ?? .distantPast
            return a.state == .post ? da > db : da < db
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
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

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
                    if auth.isAuthenticated {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            if isDeleting { ProgressView().controlSize(.small) } else { Text("Delete Account") }
                        }
                        .disabled(isDeleting)
                    }
                }
                Color.clear.frame(height: 0)
                    .confirmationDialog("Delete your GuideStream account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete Account", role: .destructive) { Task { await deleteAccount() } }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This permanently removes your account, watchlist, followed creators, teams and all associated data. It can't be undone.")
                    }
                if let deleteError {
                    Text(deleteError).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.red.opacity(0.9))
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Which services do you have?").font(.system(size: 17, weight: .semibold))
                            Text("\(selected.count) selected · edit to personalise what shows up on your feed")
                                .font(.system(size: 12)).foregroundStyle(MacColor.text2)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").foregroundStyle(MacColor.text3)
                            TextField("Search all services", text: $filter).textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.white.opacity(0.05), in: Capsule())
                        .overlay(Capsule().stroke(MacColor.hairline, lineWidth: 1))
                        .frame(width: 240)
                        Button { auth.setSelectedServices(selected) } label: {
                            Label("Save", systemImage: "checkmark")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(selected == auth.selectedServices ? Color.white.opacity(0.12) : MacColor.orange, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("s")
                        .disabled(selected == auth.selectedServices)
                    }

                    if !popular.isEmpty {
                        Text("Most popular").font(.system(size: 13, weight: .semibold)).foregroundStyle(MacColor.text2)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 124), spacing: 16)],
                                  alignment: .leading, spacing: 18) {
                            ForEach(popular) { s in serviceTile(s) }
                        }
                    }
                    if !allServices.isEmpty {
                        Text("All services · A–Z").font(.system(size: 13, weight: .semibold)).foregroundStyle(MacColor.text2)
                            .padding(.top, 6)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(allServices) { s in serviceRow(s) }
                        }
                    }
                    if popular.isEmpty && allServices.isEmpty {
                        Text("No services match").font(.system(size: 13)).foregroundStyle(MacColor.text2)
                    }
                }

                Text("GuideStream TV for Mac \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.system(size: 11)).foregroundStyle(MacColor.text3)
            }
            .padding(MacLayout.contentPadding)
        }
        .onAppear { selected = auth.selectedServices }
    }

    /// The phone's "Most popular" tiles: the first 18 of its catalogue.
    private var popular: [StreamingService] {
        Array(StreamingCatalog.all.prefix(18)).filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
    }

    /// Everything else, A–Z, as small rows (the phone lists the full catalogue here).
    private var allServices: [StreamingService] {
        StreamingCatalog.all.dropFirst(18)
            .filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func toggle(_ id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        }
    }

    /// Large tile, as the phone's ServiceTile: brand square, white ring and
    /// orange check when selected, dimmed when not.
    private func serviceTile(_ s: StreamingService) -> some View {
        let on = selected.contains(s.id)
        return Button { toggle(s.id) } label: {
            VStack(spacing: 8) {
                TVServiceBrandMark(providerName: s.name, size: 96, catalogId: s.id, cornerRadius: 16)
                    .opacity(on ? 1 : 0.52)
                    .overlay {
                        if on { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white, lineWidth: 3.5) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if on {
                            ZStack {
                                Circle().fill(MacColor.orange).frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(MacColor.navy, lineWidth: 2))
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                            }
                            .offset(x: 7, y: -7)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(s.name).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(on ? .white : Color.white.opacity(0.4))
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Small row, as the phone's A–Z list: mini brand icon, name, switch.
    private func serviceRow(_ s: StreamingService) -> some View {
        let on = selected.contains(s.id)
        return Button { toggle(s.id) } label: {
            HStack(spacing: 10) {
                TVServiceBrandMark(providerName: s.name, size: 30, catalogId: s.id, cornerRadius: 8)
                Text(s.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                ZStack {
                    Capsule().fill(on ? MacColor.orange : Color.white.opacity(0.15)).frame(width: 36, height: 21)
                    Circle().fill(.white).frame(width: 17, height: 17).offset(x: on ? 7.5 : -7.5)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MacColor.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


extension MacProfileView {
    /// Same call as the iPhone's ProfileDestinations.deleteAccount: the
    /// `delete_account` edge function (verify_jwt) purges the caller's rows
    /// and deletes the auth user, then we sign out locally.
    func deleteAccount() async {
        guard let token = (try? await TVSupabaseManager.shared.client.auth.session)?.accessToken,
              let url = URL(string: "\(TVSupabaseConfig.url)/functions/v1/delete_account") else {
            deleteError = "Couldn't delete your account. Check your connection and try again."
            return
        }
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(TVSupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                deleteError = "Couldn't delete your account. Check your connection and try again."
                return
            }
            await auth.signOut()
        } catch {
            deleteError = "Couldn't delete your account. Check your connection and try again."
        }
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
