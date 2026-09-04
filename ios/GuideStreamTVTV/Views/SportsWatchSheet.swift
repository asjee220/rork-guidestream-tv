//
//  SportsWatchSheet.swift
//  GuideStreamTV
//
//  Bottom sheet presented when a user taps Watch / a game card in the Sports
//  tab. Mirrors the visual structure of `EpisodeDetailSheet` / `PlayOnBottomSheet`
//  so the experience is consistent with the rest of the app — header row,
//  actions row, About, Where to Watch, big watch CTA.
//

import SwiftUI
import UIKit

/// Focus targets on the sheet. tvOS selection here is a 2pt white stroke on
/// each control's own shape — never `.buttonStyle(.plain)`, which lays a white
/// slab over whatever it wraps even under `.focusEffectDisabled()`.
private enum SportsSheetFocus: Hashable {
    case remind, like, favoriteAway, favoriteHome, watch, watchlist, close
}

struct SportsWatchSheet: View {
    let game: SportsGame
    @Environment(\.dismiss) private var dismiss

    @State private var isReminderSet: Bool = false
    @State private var favorites = TVTeamFavoritesService.shared
    @FocusState private var focus: SportsSheetFocus?
    @State private var streams = StreamsViewModel.shared
    @State private var social = SocialViewModel.shared
    @State private var isToggleSaving: Bool = false
    @State private var isTogglingLike: Bool = false

    private var awayColor: Color { game.away.primaryHex.map { Color(hex: $0) } ?? Color(white: 0.18) }
    private var homeColor: Color { game.home.primaryHex.map { Color(hex: $0) } ?? Color(white: 0.18) }
    private var primaryBroadcast: String? { game.broadcasts.first }

    private var gameTitle: String {
        "\(game.away.shortName) vs \(game.home.shortName)"
    }

    private var metaText: String {
        let parts = [game.sport, game.statusDetail].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private var aboutText: String {
        switch game.state {
        case .live:
            if let b = primaryBroadcast {
                return "Live now on \(b). Tap watch to open the broadcast and jump into the action."
            }
            return "Live now. Tap watch to find the broadcast and start streaming."
        case .pre:
            let when = formattedStartLocal
            if let b = primaryBroadcast {
                if when.isEmpty {
                    return "Coming soon on \(b). Set a reminder so you don't miss tip-off — or tap watch when the broadcast goes live."
                }
                return "\(when) on \(b). Set a reminder so you don't miss tip-off — or tap watch when the broadcast goes live."
            }
            if when.isEmpty {
                return "Broadcast info will appear closer to game time. Set a reminder to get a heads-up."
            }
            return "\(when). Broadcast info will appear closer to game time. Set a reminder to get a heads-up."
        case .post:
            let winnerLine = winnerSummary
            if let b = primaryBroadcast {
                return "\(winnerLine) Watch the recap and highlights on \(b)."
            }
            return "\(winnerLine) Highlights will be available shortly after the final whistle."
        }
    }

    private var winnerSummary: String {
        let away = game.away
        let home = game.home
        if away.isWinner {
            return "\(away.shortName) won \(away.score)–\(home.score) over \(home.shortName)."
        }
        if home.isWinner {
            return "\(home.shortName) won \(home.score)–\(away.score) over \(away.shortName)."
        }
        return "Final: \(away.shortName) \(away.score), \(home.shortName) \(home.score)."
    }

    private var formattedStartLocal: String {
        guard let date = game.startDate else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 18)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                actionsRow
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                whereToWatchSection
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                watchActions
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                aboutSection
                    .padding(.horizontal, 20)
                    .padding(.top, 28)

                closeButton
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color(red: 0x06/255, green: 0x0C/255, blue: 0x18/255).ignoresSafeArea())
        #if !os(tvOS)
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        #endif
        .onAppear {
            WatchIntentLogger.shared.log(
                eventType: .episodeDetailViewed,
                titleId: WatchIntentLogger.titleSlug("\(game.away.abbreviation)-\(game.home.abbreviation)-\(game.sport)"),
                platformId: (primaryBroadcast ?? "").lowercased(),
                metadata: [
                    "sport": game.sport,
                    "state": game.state.rawValue,
                    "broadcasts": game.broadcasts
                ]
            )
        }
        .task(id: gameSaveId) {
            await social.refreshCounts(titleId: gameSaveId)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 16) {
            gameThumbnail
                .frame(width: 170, height: 232)
                .clipShape(.rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 12) {
                Text(gameTitle)
                    .scaledFont(size: 44, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(metaText)
                    .scaledFont(size: 22)
                    .foregroundStyle(Color.white.opacity(0.55))

                HStack(spacing: 10) {
                    statusChip
                    Text(game.sport.uppercased())
                        .scaledFont(size: 18, weight: .heavy)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .padding(.top, 2)

                if game.state != .pre {
                    liveScoreRow
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var gameThumbnail: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                awayColor
                VStack(alignment: .leading, spacing: 4) {
                    Text("AWAY")
                        .scaledFont(size: 14, weight: .heavy)
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.65))
                    HStack(spacing: 6) {
                        if let logoURL = game.away.logoURL, !logoURL.isEmpty, let url = URL(string: logoURL) {
                            AsyncImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFit().frame(width: 34, height: 34)
                                } else {
                                    EmptyView()
                                }
                            }
                        }
                        Text(game.away.abbreviation)
                            .scaledFont(size: 32, weight: .black)
                            .foregroundStyle(.white)
                    }
                }
                .padding(10)
            }

            ZStack(alignment: .bottomTrailing) {
                homeColor
                VStack(alignment: .trailing, spacing: 4) {
                    Text("HOME")
                        .scaledFont(size: 14, weight: .heavy)
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.65))
                    HStack(spacing: 6) {
                        Text(game.home.abbreviation)
                            .scaledFont(size: 32, weight: .black)
                            .foregroundStyle(.white)
                        if let logoURL = game.home.logoURL, !logoURL.isEmpty, let url = URL(string: logoURL) {
                            AsyncImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFit().frame(width: 34, height: 34)
                                } else {
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .overlay(
            // Diagonal seam between team colors.
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .frame(height: 1)
        )
        .overlay(alignment: .center) {
            Text("VS")
                .scaledFont(size: 17, weight: .black)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Circle().fill(.black.opacity(0.5))
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                )
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        switch game.state {
        case .live:
            HStack(spacing: 5) {
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                Text("LIVE")
                    .scaledFont(size: 18, weight: .heavy)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color(hex: "E50914")))
        case .pre:
            Text("UPCOMING")
                .scaledFont(size: 18, weight: .heavy)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.orange))
        case .post:
            Text("FINAL")
                .scaledFont(size: 18, weight: .heavy)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.18)))
        }
    }

    private var liveScoreRow: some View {
        HStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 3) {
                Text(game.away.abbreviation)
                    .scaledFont(size: 18, weight: .heavy)
                    .foregroundStyle(Color.white.opacity(0.6))
                Text(game.away.score)
                    .scaledFont(size: 40, weight: .black)
                    .foregroundStyle(game.away.isWinner ? .white : Color.white.opacity(0.7))
            }
            Text("–")
                .scaledFont(size: 28, weight: .bold)
                .foregroundStyle(Color.white.opacity(0.3))
            VStack(alignment: .leading, spacing: 3) {
                Text(game.home.abbreviation)
                    .scaledFont(size: 18, weight: .heavy)
                    .foregroundStyle(Color.white.opacity(0.6))
                Text(game.home.score)
                    .scaledFont(size: 40, weight: .black)
                    .foregroundStyle(game.home.isWinner ? .white : Color.white.opacity(0.7))
            }
        }
    }

    // MARK: - Actions

    private var actionsRow: some View {
        let key = gameSaveId
        let isLiked = social.isLiked(key)
        let likeCount = social.likes(key)
        return HStack(spacing: 0) {
            circleAction(
                icon: isReminderSet ? "bell.badge.fill" : "alarm",
                label: "Remind me",
                count: nil,
                tint: isReminderSet ? Color.orange : .white,
                showDot: isReminderSet,
                focusKey: .remind
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isReminderSet.toggle() }
            }
            .frame(maxWidth: .infinity)

            circleAction(
                icon: isLiked ? "heart.fill" : "heart",
                label: "Like",
                count: likeCount,
                tint: isLiked ? Color.orange : .white,
                showDot: false,
                focusKey: .like,
                isHighlighted: isLiked
            ) {
                guard !isTogglingLike else { return }
                isTogglingLike = true
                Task {
                    await social.toggleLike(titleId: key)
                    await MainActor.run { isTogglingLike = false }
                }
            }
            .frame(maxWidth: .infinity)

            favoriteAction(team: game.away, focusKey: .favoriteAway)
                .frame(maxWidth: .infinity)

            favoriteAction(team: game.home, focusKey: .favoriteHome)
                .frame(maxWidth: .infinity)
        }
    }

    /// Star toggle for one of the two teams, wired to the same
    /// `TVTeamFavoritesService` My Teams and the Schedule read. A team already
    /// followed opens filled and highlighted rather than waiting to be
    /// discovered.
    private func favoriteAction(team: TVGameTeam, focusKey: SportsSheetFocus) -> some View {
        let isFavorite = favorites.isFavorite(team.uid)
        return circleAction(
            icon: isFavorite ? "star.fill" : "star",
            label: team.abbreviation,
            count: nil,
            tint: isFavorite ? Color.orange : .white,
            showDot: false,
            focusKey: focusKey,
            isHighlighted: isFavorite
        ) {
            Task { await favorites.toggle(team: team, league: game.leagueShort, sport: game.sport) }
        }
        .disabled(team.uid == nil)
    }

    /// One circular action. `isHighlighted` is the resting "already on" state
    /// — a followed team, not a focused one; focus stays the 2pt white stroke.
    private func circleAction(
        icon: String,
        label: String,
        count: Int?,
        tint: Color,
        showDot: Bool,
        focusKey: SportsSheetFocus,
        isHighlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focus == focusKey
        return Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isHighlighted ? Color.orange.opacity(0.22) : Color.white.opacity(0.08))
                        .frame(width: 84, height: 84)
                    if isHighlighted {
                        Circle()
                            .stroke(Color.orange, lineWidth: 2)
                            .frame(width: 84, height: 84)
                    }
                    // Focus is the house 2pt white stroke on the shape itself.
                    Circle()
                        .stroke(isFocused ? Color.white : Color.clear, lineWidth: 2)
                        .frame(width: 84, height: 84)
                    Image(systemName: icon)
                        .scaledFont(size: 34, weight: .regular)
                        .foregroundStyle(tint)
                    if showDot {
                        Circle()
                            .fill(Color(red: 0x3D/255, green: 0xE0/255, blue: 0x6A/255))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color(red: 0x06/255, green: 0x0C/255, blue: 0x18/255), lineWidth: 3))
                            .offset(x: 26, y: -26)
                    }
                }
                VStack(spacing: 3) {
                    Text(label)
                        .scaledFont(size: 20)
                        .foregroundStyle(Color.white.opacity(isFocused ? 1 : 0.7))
                        .lineLimit(1)
                    if let count, count > 0 {
                        Text(formatSocialCount(count))
                            .scaledFont(size: 18, weight: .heavy)
                            .foregroundStyle(.white)
                    }
                }
            }
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }
        // Never `.plain` on tvOS: it lays a white slab over the label on focus
        // even under `.focusEffectDisabled()`.
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focus, equals: focusKey)
    }

    /// Compact count formatting used by the actions row, matching the
    /// same rule the EpisodeDetailSheet uses so likes/comments look
    /// consistent across the app.
    private func formatSocialCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ABOUT")
                .scaledFont(size: 19, weight: .heavy)
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(aboutText)
                .scaledFont(size: 23)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Where to watch

    private var whereToWatchSection: some View {
        // Enriched with streaming simulcast companions (ESPN's scoreboard only
        // reports the linear carrier); `game.broadcasts` itself stays untouched.
        let enriched = TVSportsSimulcast.enrich(game.broadcasts)
        return VStack(alignment: .leading, spacing: 10) {
            Text("WHERE TO WATCH")
                .scaledFont(size: 19, weight: .heavy)
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.45))

            if enriched.isEmpty {
                Text("Broadcast not announced yet — check back closer to game time.")
                    .scaledFont(size: 21)
                    .foregroundStyle(Color.white.opacity(0.5))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(enriched, id: \.self) { name in
                            broadcastChip(name)
                        }
                    }
                }
                .scrollClipDisabled()
            }

            if !enriched.isEmpty {
                Text(availabilityLabel)
                    .scaledFont(size: 21)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var availabilityLabel: String {
        switch game.state {
        case .live: return "Streaming live now"
        case .pre:
            let when = formattedStartLocal
            return when.isEmpty ? "Coverage time to be confirmed" : "Coverage starts at \(when)"
        case .post: return "Highlights and replay available"
        }
    }

    private func broadcastChip(_ name: String) -> some View {
        Text(name)
            .scaledFont(size: 20, weight: .heavy)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(Capsule().fill(broadcastColor(name)))
    }

    private func broadcastColor(_ name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("espn") { return Color(hex: "CC0000") }
        if lower.contains("peacock") { return Color(white: 0.10) }
        if lower.contains("prime") || lower.contains("amazon") { return Color(hex: "00A8E0") }
        if lower.contains("apple") { return Color(white: 0.12) }
        if lower.contains("paramount") { return Color(hex: "0064FF") }
        if lower.contains("max") || lower.contains("hbo") { return Color(hex: "002BE7") }
        if lower.contains("nbc") { return Color(hex: "FCB900") }
        if lower.contains("fox") { return Color(hex: "003366") }
        if lower.contains("cbs") { return Color(hex: "003366") }
        if lower.contains("abc") { return Color(white: 0.10) }
        if lower.contains("tnt") || lower.contains("tbs") { return Color(hex: "E2231A") }
        if lower.contains("nba") { return Color(hex: "1D428A") }
        if lower.contains("nfl") { return Color(hex: "013369") }
        if lower.contains("mlb") { return Color(hex: "002D72") }
        if lower.contains("nhl") { return Color(hex: "0A0E14") }
        if lower.contains("ufc") { return Color(hex: "D20A0A") }
        return Color(red: 0x6A/255, green: 0x3F/255, blue: 0xE0/255)
    }

    // MARK: - Watch CTA

    private var watchActions: some View {
        // `.top` alignment keeps the full-width Watch CTA pinned to the top
        // while the watchlist circle + label hangs below — matches the
        // Reels rail rhythm so the affordance feels consistent.
        // The CTA no longer stretches edge to edge — at TV width a full-bleed
        // capsule reads as a banner rather than a button. It sizes to its own
        // label up to a cap, and the trailing Spacer keeps it and the watch-list
        // circle together on the leading side.
        HStack(alignment: .top, spacing: 24) {
            watchButton
            watchlistButton
            Spacer(minLength: 0)
        }
    }

    private var watchButton: some View {
        let platform = primaryBroadcast ?? ""
        let canWatch = !platform.isEmpty
        return Button {
            let slug = WatchIntentLogger.titleSlug("\(game.away.abbreviation)-\(game.home.abbreviation)-\(game.sport)")
            WatchIntentLogger.shared.log(
                eventType: .deeplinkFired,
                titleId: slug,
                platformId: platform.lowercased(),
                metadata: [
                    "sport": game.sport,
                    "live": String(game.state == .live),
                    "platform_name": platform
                ]
            )
            StreamingDeepLinker.open(
                platform: platform,
                title: "\(game.away.displayName) vs \(game.home.displayName)",
                titleSlug: slug
            )
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: game.state == .live ? "play.fill" : "play.tv.fill")
                    .scaledFont(size: 26, weight: .bold)
                Text(canWatch ? "Watch on \(platform)" : "Broadcast TBA")
                    .scaledFont(size: 28, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 52)
            .frame(height: 92)
            .background(Capsule().fill(canWatch ? Color.orange : Color.white.opacity(0.15)))
            .overlay(Capsule().stroke(focus == .watch ? Color.white : Color.clear, lineWidth: 2))
            .shadow(color: canWatch ? Color.orange.opacity(0.55) : .clear, radius: 22, y: 0)
            .scaleEffect(focus == .watch ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.15), value: focus == .watch)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focus, equals: .watch)
        .disabled(!canWatch)
    }

    /// Stable id used to identify the game in the user's watch list.
    private var gameSaveId: String {
        WatchIntentLogger.titleSlug("\(game.away.abbreviation)-\(game.home.abbreviation)-\(game.sport)")
    }

    /// True when the user has already saved this game to their watch list.
    private var isSaved: Bool {
        streams.userStreams.contains { $0.titleId == gameSaveId }
    }

    /// Circular + watchlist button mirroring the Reels rail affordance. Lives
    /// next to the main "Watch on \(broadcaster)" CTA so users can park a game
    /// in their list with one tap without leaving the sheet.
    ///
    /// * **Not saved** — solid orange circle with a `plus` glyph + "Watch List"
    ///   label below.
    /// * **Saved** — transparent circle with a white stroke (outlined) + a
    ///   checkmark glyph and "Saved" label below.
    @ViewBuilder
    private var watchlistButton: some View {
        Button {
            toggleWatchList()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if isSaved {
                        Circle()
                            .fill(Color.clear)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                    } else {
                        Circle()
                            .fill(Color.orange)
                            .shadow(color: Color.orange.opacity(0.55), radius: 14, y: 0)
                    }
                    if isToggleSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: isSaved ? "checkmark" : "plus")
                            .scaledFont(size: 34, weight: .bold)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 84, height: 84)
                .overlay(
                    Circle().stroke(focus == .watchlist ? Color.white : Color.clear, lineWidth: 2)
                )

                Text(isSaved ? "Saved" : "Watch List")
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .scaleEffect(focus == .watchlist ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.15), value: focus == .watchlist)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focus, equals: .watchlist)
        .disabled(isToggleSaving)
        .accessibilityLabel(isSaved ? "Saved to watch list. Tap to remove." : "Add game to watch list")
    }

    private func toggleWatchList() {
        let key = gameSaveId
        let snapshotSaved = isSaved
        isToggleSaving = true
        Task {
            if snapshotSaved {
                await streams.removeFromMyStreams(titleId: key)
            } else {
                await streams.addToMyStreams(
                    titleId: key,
                    title: gameTitle,
                    posterUrl: nil,
                    platform: primaryBroadcast
                )
            }
            await MainActor.run { isToggleSaving = false }
        }
    }

    private var closeButton: some View {
        Button(action: { dismiss() }) {
            HStack(spacing: 10) {
                Text("Close")
                    .scaledFont(size: 24, weight: .semibold)
                Image(systemName: "xmark")
                    .scaledFont(size: 20, weight: .semibold)
            }
            .foregroundStyle(Color.white.opacity(focus == .close ? 1 : 0.85))
            .padding(.horizontal, 30)
            .padding(.vertical, 14)
            .overlay(Capsule().stroke(focus == .close ? Color.white : Color.clear, lineWidth: 2))
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focus, equals: .close)
    }
}

#Preview {
    SportsWatchSheet(
        game: SportsGame(
            id: "preview",
            sport: "NBA",
            leagueShort: "NBA",
            state: .live,
            statusDetail: "3rd Qtr · 8:42",
            startDate: Date(),
            home: GameTeam(abbreviation: "MIA", displayName: "Miami Heat", shortName: "Heat", score: "82", primaryHex: "CE1141", isWinner: false),
            away: GameTeam(abbreviation: "NYK", displayName: "New York Knicks", shortName: "Knicks", score: "87", primaryHex: "006BB6", isWinner: true),
            broadcasts: ["ESPN", "TNT"]
        )
    )
    .preferredColorScheme(.dark)
}
