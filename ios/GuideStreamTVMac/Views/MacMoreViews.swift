//
//  MacMoreViews.swift
//  GuideStreamTVMac
//
//  Schedule (TVScheduleService), creator pages (TVCreatorService) and the
//  sports game sheet — the Apple TV data layer under Mac layouts.
//

import SwiftUI

// MARK: - Schedule

struct MacScheduleView: View {
    @State private var schedule = TVScheduleService.shared
    @State private var weekOffset = 0
    @Environment(\.openTitle) private var openTitle
    @Environment(\.openGame) private var openGame

    private var weekStart: Date {
        let base = TVScheduleWeek.start(of: Date())
        return Calendar.current.date(byAdding: .day, value: 7 * weekOffset, to: base) ?? base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(weekOffset <= 0)
                Text(TVScheduleWeek.rangeLabel(for: weekStart)).font(.system(size: 15, weight: .semibold))
                    .frame(minWidth: 140)
                Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(weekOffset >= TVScheduleWeek.maxOffset)
                if weekOffset != 0 { Button("This week") { weekOffset = 0 } }
                Spacer()
                if schedule.isLoadingEpisodes || schedule.isLoadingGames { ProgressView().controlSize(.small) }
            }
            .buttonStyle(.bordered)

            if !AuthViewModel.shared.isAuthenticated {
                MacEmptyState(icon: "calendar", title: "Sign in to see your schedule",
                              message: "Episodes of shows you save and games for teams you follow land here.")
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 7),
                              alignment: .leading, spacing: 10) {
                        ForEach(TVScheduleWeek.days(from: weekStart), id: \.self) { day in dayColumn(day) }
                    }
                }
            }
        }
        .padding(MacLayout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await TVStreamsViewModel.shared.fetchUserStreams(); await schedule.loadEpisodes() }
        .task(id: weekOffset) {
            await TVTeamFavoritesService.shared.load()
            await schedule.loadGames(weekStart: weekStart)
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let cal = Calendar.current
        let episodes = schedule.episodes.filter { cal.isDate($0.airDay, inSameDayAs: day) }
        let games = schedule.games.filter { $0.startDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }
        let today = cal.isDateInToday(day)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 11, weight: .bold)).tracking(0.8)
                    .foregroundStyle(today ? MacColor.orange : MacColor.text3)
                Text(day.formatted(.dateTime.day())).font(.system(size: 20, weight: .bold))
                    .foregroundStyle(today ? MacColor.orange : .white)
            }
            if episodes.isEmpty && games.isEmpty {
                Text("—").font(.system(size: 12)).foregroundStyle(MacColor.text3)
            }
            ForEach(episodes) { ep in
                Button {
                    if let id = TVTitleID.tmdbId(from: ep.titleId) {
                        openTitle(MacTitleRef(titleId: "tmdb:tv:\(id)", tmdbId: id, isTV: true, title: ep.showTitle, posterUrl: ep.posterUrl))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        TVRemoteImage(urlString: ep.posterUrl, contentMode: .fill)
                            .aspectRatio(2 / 3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(ep.showTitle).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        Text(ep.isSeasonFinale ? "\(ep.episodeLabel) · Finale" : ep.episodeLabel)
                            .font(.system(size: 11)).foregroundStyle(ep.isSeasonFinale ? MacColor.orange : MacColor.text3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(games) { g in
                Button { openGame(g) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(g.away.abbreviation) @ \(g.home.abbreviation)").font(.system(size: 12, weight: .bold))
                        Text(g.startDate?.formatted(date: .omitted, time: .shortened) ?? g.statusDetail)
                            .font(.system(size: 11)).foregroundStyle(MacColor.text3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(MacColor.elevated, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(today ? MacColor.orange.opacity(0.06) : MacColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(today ? MacColor.orange.opacity(0.4) : MacColor.hairline, lineWidth: 1))
    }
}

// MARK: - Creator page

struct MacCreatorRef: Identifiable, Hashable {
    let titleId: String
    var id: String { titleId }
}

struct MacCreatorSheet: View {
    let ref: MacCreatorRef
    @Environment(\.dismiss) private var dismiss
    @State private var source: TVCreatorSource?
    @State private var meta: TVChannelMetaResponse?
    @State private var live: TVLiveStatus?
    @State private var episodes: [TVCreatorEpisode] = []
    @State private var playing: String?
    @State private var streams = TVStreamsViewModel.shared

    private var kind: TVCreatorKind? { TVCreatorKind.from(titleId: ref.titleId) }
    private var name: String { meta?.channel?.name ?? source?.displayName ?? "Creator" }
    private var avatar: String? { meta?.channel?.avatar ?? source?.imageUrl }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                TVRemoteImage(urlString: avatar, contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(name).font(.system(size: 22, weight: .bold))
                        if live?.isLive == true {
                            Text("LIVE").font(.system(size: 10, weight: .heavy)).padding(.horizontal, 7).padding(.vertical, 3)
                                .background(MacColor.live, in: Capsule())
                        }
                    }
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(MacColor.text2)
                }
                Spacer()
                Button { Task { await toggleFollow() } } label: {
                    Label(isFollowing ? "Following" : "Follow", systemImage: isFollowing ? "checkmark" : "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(isFollowing ? Color.white.opacity(0.12) : MacColor.orange, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(!AuthViewModel.shared.isAuthenticated)
                if let url = MacCreatorLinks.url(for: ref.titleId) ?? source?.channelUrl.flatMap(URL.init(string:)) {
                    Button { MacLinkOpener.open(url) } label: { Image(systemName: "arrow.up.right.square") }
                        .buttonStyle(.plain).font(.system(size: 18)).help("Open on \(kind?.displayLabel ?? "the web")")
                }
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            .padding(20)

            if let playing {
                MacYouTubePlayer(videoId: playing)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .id(playing)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let bio = meta?.channel?.description ?? source?.description, !bio.isEmpty, playing == nil {
                        Text(bio).font(.system(size: 13)).foregroundStyle(MacColor.text2).lineLimit(4)
                    }
                    if let uploads = meta?.uploads, !uploads.isEmpty {
                        Text("Latest").font(.system(size: 15, weight: .semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], alignment: .leading, spacing: 16) {
                            ForEach(uploads) { u in uploadCard(u) }
                        }
                    } else if !episodes.isEmpty {
                        Text("Latest").font(.system(size: 15, weight: .semibold))
                        ForEach(episodes) { ep in episodeRow(ep) }
                    } else if source != nil {
                        Text("No recent uploads.").font(.system(size: 13)).foregroundStyle(MacColor.text2)
                    } else {
                        ProgressView()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 900, height: 720)
        .background(MacColor.navy)
        .task { await load() }
    }

    private var subtitle: String {
        var parts: [String] = [kind?.displayLabel ?? "Creator"]
        if let subs = meta?.stats?.subscribers, subs > 0 { parts.append("\(Self.compact(subs)) subscribers") }
        if let cat = source?.category, !cat.isEmpty { parts.append(cat) }
        return parts.joined(separator: " · ")
    }

    private var isFollowing: Bool { streams.contains(titleId: ref.titleId) }

    private func toggleFollow() async {
        if isFollowing { await streams.remove(titleId: ref.titleId) }
        else { await streams.add(titleId: ref.titleId, title: name, posterUrl: avatar, platform: kind?.rawValue) }
    }

    private func uploadCard(_ u: TVChannelMetaResponse.Upload) -> some View {
        Button {
            if kind == .youtube { playing = u.videoId }
            else if let url = URL(string: u.deepLink) { MacLinkOpener.open(url) }
            WatchIntentLogger.shared.log(eventType: .cardTapped, titleId: ref.titleId, platformId: kind?.rawValue,
                                         metadata: ["surface": "mac_creator", "video_id": u.videoId])
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    TVRemoteImage(urlString: u.thumbnail, contentMode: .fill)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    if u.durationSeconds > 0 {
                        Text(Self.duration(u.durationSeconds)).font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }
                Text(u.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text(u.views > 0 ? "\(Self.compact(u.views)) views" : "").font(.system(size: 11)).foregroundStyle(MacColor.text3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func episodeRow(_ ep: TVCreatorEpisode) -> some View {
        Button {
            if let link = ep.deepLinkUrl, let url = URL(string: link) { MacLinkOpener.open(url) }
        } label: {
            HStack(spacing: 12) {
                TVRemoteImage(urlString: ep.thumbnailUrl ?? ep.posterUrl, contentMode: .fill)
                    .frame(width: 120, height: 68).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(ep.title ?? "Episode").font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    if let d = ep.releasedAt {
                        Text(d.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11)).foregroundStyle(MacColor.text3)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        async let s = TVCreatorService.fetchSource(titleId: ref.titleId)
        async let m = TVCreatorService.fetchChannelMeta(titleId: ref.titleId)
        async let l = TVCreatorService.fetchLiveStatus(titleId: ref.titleId)
        async let e = TVCreatorService.fetchEpisodes(titleId: ref.titleId)
        (source, meta, live, episodes) = await (s, m, l, e)
    }

    static func compact(_ n: Int64) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    static func duration(_ s: Int) -> String {
        s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Game sheet

struct MacGameSheet: View {
    let game: TVSportsGame
    @Environment(\.dismiss) private var dismiss
    @State private var favorites = TVTeamFavoritesService.shared

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text(game.leagueShort.isEmpty ? game.sport : game.leagueShort.uppercased())
                    .font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(MacColor.text2)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .center, spacing: 24) {
                teamColumn(game.away)
                VStack(spacing: 6) {
                    if game.state == .pre {
                        Text(game.startDate?.formatted(date: .abbreviated, time: .shortened) ?? game.statusDetail)
                            .font(.system(size: 15, weight: .semibold))
                    } else {
                        Text("\(game.away.score) – \(game.home.score)").font(.system(size: 38, weight: .heavy)).monospacedDigit()
                        Text(game.statusDetail).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(game.state.isLive ? MacColor.live : MacColor.text2)
                    }
                }
                .frame(minWidth: 160)
                teamColumn(game.home)
            }
            if !game.broadcasts.isEmpty {
                VStack(spacing: 8) {
                    Text("WATCH ON").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(MacColor.text3)
                    HStack(spacing: 8) {
                        ForEach(sortedBroadcasts, id: \.self) { b in
                            let mine = AuthViewModel.shared.subscribesToService(named: b)
                            Text(b).font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(mine ? MacColor.orange : MacColor.elevated, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(mine ? Color(red: 0.03, green: 0.02, blue: 0.02) : .white)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(MacColor.navy)
        .onAppear {
            WatchIntentLogger.shared.log(eventType: .cardTapped,
                                         titleId: WatchIntentLogger.titleSlug("\(game.away.abbreviation)-\(game.home.abbreviation)-\(game.sport)"),
                                         platformId: (game.broadcasts.first ?? "").lowercased(),
                                         metadata: ["surface": "mac_game", "kind": "sport"])
        }
    }

    /// Services the viewer subscribes to first, as on the phone.
    private var sortedBroadcasts: [String] {
        game.broadcasts.enumerated().sorted { a, b in
            let sa = AuthViewModel.shared.subscribesToService(named: a.element)
            let sb = AuthViewModel.shared.subscribesToService(named: b.element)
            return sa != sb ? sa : a.offset < b.offset
        }.map(\.element)
    }

    private func teamColumn(_ t: TVGameTeam) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.fromHex(t.primaryHex) ?? MacColor.elevated)
                if let logo = t.logoURL { TVRemoteImage(urlString: logo, contentMode: .fit).padding(12) }
                else { Text(t.abbreviation).font(.system(size: 16, weight: .bold)) }
            }
            .frame(width: 72, height: 72)
            Text(t.displayName).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2)
            if t.uid != nil {
                Button {
                    Task { await favorites.toggle(team: t, league: game.leagueShort, sport: game.sport) }
                } label: {
                    Image(systemName: favorites.isFavorite(t.uid) ? "star.fill" : "star")
                        .foregroundStyle(favorites.isFavorite(t.uid) ? MacColor.orange : MacColor.text2)
                }
                .buttonStyle(.plain)
                .disabled(!AuthViewModel.shared.isAuthenticated)
                .help(favorites.isFavorite(t.uid) ? "Remove from My Teams" : "Add to My Teams")
            }
        }
        .frame(width: 150)
    }
}

// MARK: - Environment routes

private struct OpenGameKey: EnvironmentKey { static let defaultValue: (TVSportsGame) -> Void = { _ in } }
private struct OpenCreatorKey: EnvironmentKey { static let defaultValue: (String) -> Void = { _ in } }

extension EnvironmentValues {
    var openGame: (TVSportsGame) -> Void {
        get { self[OpenGameKey.self] }
        set { self[OpenGameKey.self] = newValue }
    }
    /// Opens the creator sheet for a "yt:", "tw:", "kick:" or "pod:" title id.
    var openCreator: (String) -> Void {
        get { self[OpenCreatorKey.self] }
        set { self[OpenCreatorKey.self] = newValue }
    }
}
