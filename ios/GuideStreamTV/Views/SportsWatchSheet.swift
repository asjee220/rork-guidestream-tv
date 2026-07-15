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

struct SportsWatchSheet: View {
    let game: SportsGame
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @State private var showCastSheet: Bool = false
    @State private var favorites = TeamFavoritesService.shared
    @State private var streams = StreamsViewModel.shared
    @State private var social = SocialViewModel.shared
    @State private var isToggleSaving: Bool = false
    @State private var isTogglingLike: Bool = false
    @State private var adDismissed: Bool = false
    @State private var selectedBroadcast: String?

    private var awayColor: Color { game.away.primaryHex.map { Color(hex: $0) } ?? Color(white: 0.18) }
    private var homeColor: Color { game.home.primaryHex.map { Color(hex: $0) } ?? Color(white: 0.18) }
    private var primaryBroadcast: String? { game.broadcasts.first }

    /// `game.broadcasts` de-duplicated preserving first-seen order, then
    /// stable-sorted so broadcasts the user subscribes to come first — the
    /// same subscribed-service ordering used on the movie / TV detail screen.
    private var sortedBroadcasts: [String] {
        var seen = Set<String>()
        let unique = game.broadcasts.filter { seen.insert($0).inserted }
        return unique.enumerated().sorted { a, b in
            let aSub = AuthViewModel.shared.subscribesToService(named: a.element)
            let bSub = AuthViewModel.shared.subscribesToService(named: b.element)
            if aSub != bSub { return aSub }
            return a.offset < b.offset
        }.map { $0.element }
    }

    /// The broadcast the Watch CTA currently targets: the user's selection when
    /// still present in the de-duped list, otherwise the first sorted entry,
    /// otherwise the raw first broadcast.
    private var activeBroadcast: String? {
        if let sel = selectedBroadcast, sortedBroadcasts.contains(sel) {
            return sel
        }
        return sortedBroadcasts.first ?? game.broadcasts.first
    }

    private var sportsAdData:
    (serviceId: String, headline: String, subtext: String)? {
        let broadcast = (primaryBroadcast ?? "").lowercased()
        let owned = AuthViewModel.shared.selectedServices
            .map { $0.lowercased() }

        let target: String = {
            if broadcast.contains("espn") ||
                broadcast.contains("abc") { return "disney" }
            if broadcast.contains("tnt") ||
                broadcast.contains("tbs") ||
                broadcast.contains("trutv") { return "hbo" }
            if broadcast.contains("nbc") { return "peacock" }
            if broadcast.contains("cbs") { return "paramount" }
            if broadcast.contains("peacock") { return "peacock" }
            if broadcast.contains("prime") ||
                broadcast.contains("amazon") { return "prime" }
            if broadcast.contains("apple") { return "appletv" }
            if broadcast.contains("max") ||
                broadcast.contains("hbo") { return "hbo" }
            return "hulu"
        }()

        // If the user owns the target service, pick the first reasonable
        // alternative so an ad still appears.
        let resolvedTarget: String = {
            guard owned.contains(target) else { return target }
            let fallbackOrder = ["peacock", "paramount", "hbo",
                                  "disney", "prime", "appletv",
                                  "hulu", "netflix"]
            return fallbackOrder.first { !owned.contains($0) } ?? target
        }()

        let copy: [String: (String, String)] = [
            "disney": ("Stream ESPN+ & Disney Bundle",
                        "ESPN+, Disney+ & Hulu in one plan"),
            "hbo": ("Watch TNT Sports on Max",
                    "NBA, NHL & Max Originals · Try free"),
            "peacock": ("Stream NBC Sports free",
                        "NFL, Olympics & Premier League · Free tier"),
            "paramount": ("NFL on CBS & March Madness",
                          "Live sports on Paramount+ · Try free"),
            "prime": ("Thursday Night Football",
                      "Included with Prime · Prime Video"),
            "appletv": ("MLS Season Pass",
                        "Every MLS match live · Apple TV+"),
            "hulu": ("Live sports on Hulu + Live TV",
                     "ESPN, FOX, CBS, NBC & more · $82.99/mo")
        ]
        guard let c = copy[resolvedTarget] else { return nil }
        return (resolvedTarget, c.0, c.1)
    }

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
                return "\(when) on \(b). Set a reminder so you don't miss tip-off — or tap watch when the broadcast goes live."
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
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: game.startDate)
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

                sportsBanner
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                watchContextCard
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                whereToWatchChips
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                watchActions
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                secondaryPillRow
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                aboutSection
                    .padding(.horizontal, 20)
                    .padding(.top, 28)

                closeButton
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color(red: 0x13/255, green: 0x18/255, blue: 0x1D/255).ignoresSafeArea())
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .sheet(isPresented: $showCastSheet) {
            CastToTVSheet(
                isPresented: $showCastSheet,
                showTitle: gameTitle,
                platform: activeBroadcast ?? "",
                tmdbId: nil,
                isTV: false
            )
        }
        .task {
            await favorites.load()
        }
        .onAppear {
            adDismissed = false
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

    // MARK: - Sports affiliate banner

    @ViewBuilder
    private var sportsBanner: some View {
        if !adDismissed, let ad = sportsAdData,
           let service = StreamingCatalog.all
            .first(where: { $0.id == ad.serviceId }) {
            SponsoredSlotView(
                service: service,
                fallbackName: ad.headline,
                fallbackColor: .white,
                headline: ad.headline,
                subtitle: ad.subtext,
                onTap: {
                    RakutenManager.shared.openAffiliateLink(
                        serviceId: ad.serviceId,
                        metadata: [
                            "source": "sports_watch_sheet",
                            "broadcast": primaryBroadcast ?? "",
                            "sport": game.sport,
                            "state": game.state.rawValue
                        ]
                    )
                },
                onDismiss: { adDismissed = true },
                adSource: "sports_watch_sheet"
            )
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 16) {
            gameThumbnail
                .frame(width: 110, height: 150)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text(gameTitle)
                    .scaledFont(size: 24, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(metaText)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.55))

                HStack(spacing: 8) {
                    statusChip
                    Text(game.sport.uppercased())
                        .scaledFont(size: 11, weight: .heavy)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
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
                        .scaledFont(size: 8, weight: .heavy)
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.65))
                    Text(game.away.abbreviation)
                        .scaledFont(size: 22, weight: .black)
                        .foregroundStyle(.white)
                }
                .padding(10)
            }

            ZStack(alignment: .bottomTrailing) {
                homeColor
                VStack(alignment: .trailing, spacing: 4) {
                    Text("HOME")
                        .scaledFont(size: 8, weight: .heavy)
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.65))
                    Text(game.home.abbreviation)
                        .scaledFont(size: 22, weight: .black)
                        .foregroundStyle(.white)
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
                .scaledFont(size: 11, weight: .black)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
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
                    .frame(width: 6, height: 6)
                Text("LIVE")
                    .scaledFont(size: 11, weight: .heavy)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(hex: "E50914")))
        case .pre:
            Text("UPCOMING")
                .scaledFont(size: 11, weight: .heavy)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.orange))
        case .post:
            Text("FINAL")
                .scaledFont(size: 11, weight: .heavy)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.18)))
        }
    }

    private var liveScoreRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.away.abbreviation)
                    .scaledFont(size: 10, weight: .heavy)
                    .foregroundStyle(Color.white.opacity(0.6))
                Text(game.away.score)
                    .scaledFont(size: 22, weight: .black)
                    .foregroundStyle(game.away.isWinner ? .white : Color.white.opacity(0.7))
            }
            Text("–")
                .scaledFont(size: 16, weight: .bold)
                .foregroundStyle(Color.white.opacity(0.3))
            VStack(alignment: .leading, spacing: 2) {
                Text(game.home.abbreviation)
                    .scaledFont(size: 10, weight: .heavy)
                    .foregroundStyle(Color.white.opacity(0.6))
                Text(game.home.score)
                    .scaledFont(size: 22, weight: .black)
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
                icon: isLiked ? "heart.fill" : "heart",
                label: "Like",
                tint: isLiked ? Color.orange : .white,
                showDot: false
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                guard !isTogglingLike else { return }
                isTogglingLike = true
                Task {
                    await social.toggleLike(titleId: key)
                    await MainActor.run { isTogglingLike = false }
                }
            }
            .frame(maxWidth: .infinity)

            // ── Favorite teams ────────────────────────────────────────
            favoriteTeamButton(team: game.away, label: game.away.abbreviation)
                .frame(maxWidth: .infinity)
            favoriteTeamButton(team: game.home, label: game.home.abbreviation)
                .frame(maxWidth: .infinity)

            ShareLink(
                item: URL(string: "https://guidestream.tv")!,
                subject: Text(gameTitle),
                message: Text("Watch \(gameTitle) on GuideStream TV")
            ) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 54, height: 54)
                        Image(systemName: "square.and.arrow.up")
                            .scaledFont(size: 22, weight: .regular)
                            .foregroundStyle(.white)
                    }
                    Text("Share")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)

            circleAction(
                icon: "tv",
                label: "Send to TV",
                tint: .white,
                showDot: false
            ) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showCastSheet = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Favorite team button

    private func favoriteTeamButton(team: GameTeam, label: String) -> some View {
        let isFav = favorites.isFavorite(team.uid)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                await favorites.toggle(
                    team: team,
                    league: game.leagueShort,
                    sport: game.sport
                )
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 54, height: 54)
                    Image(systemName: isFav ? "star.fill" : "star")
                        .scaledFont(size: 22, weight: .regular)
                        .foregroundStyle(isFav ? Color.orange : .white)
                }
                Text(label)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func circleAction(
        icon: String,
        label: String,
        tint: Color,
        showDot: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 54, height: 54)
                    Image(systemName: icon)
                        .scaledFont(size: 22, weight: .regular)
                        .foregroundStyle(tint)
                    if showDot {
                        Circle()
                            .fill(Color(red: 0x3D/255, green: 0xE0/255, blue: 0x6A/255))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color(red: 0x13/255, green: 0x18/255, blue: 0x1D/255), lineWidth: 2))
                            .offset(x: 16, y: -16)
                    }
                }
                Text(label)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ABOUT")
                .scaledFont(size: 12, weight: .heavy)
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(aboutText)
                .scaledFont(size: 15)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Where to Watch chips

    @ViewBuilder
    private var whereToWatchChips: some View {
        let broadcasts = sortedBroadcasts
        if !broadcasts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where to Watch")
                    .scaledFont(size: 12, weight: .heavy)
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.45))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(broadcasts, id: \.self) { broadcast in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedBroadcast = broadcast
                            } label: {
                                ServiceBadge(
                                    name: broadcast,
                                    color: broadcastColor(broadcast),
                                    isSubscribed: AuthViewModel.shared.subscribesToService(named: broadcast),
                                    isSelected: activeBroadcast == broadcast
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Watch context card

    @ViewBuilder
    private var watchContextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusChip
            if game.state != .pre {
                liveScoreRow
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
    }

    // MARK: - Secondary pill row

    private var secondaryPillRow: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    router.showSportsSchedule()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .scaledFont(size: 14)
                    Text("Full schedule")
                        .scaledFont(size: 13, weight: .medium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button {
                let capturedGame = game
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    router.showGameDetail(capturedGame)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .scaledFont(size: 14)
                    Text("Game details")
                        .scaledFont(size: 13, weight: .medium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
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
        HStack(alignment: .top, spacing: 12) {
            watchButton
            watchlistButton
        }
    }

    private var watchButton: some View {
        let platform = activeBroadcast ?? ""
        let canWatch = !platform.isEmpty
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
            HStack(spacing: 8) {
                Image(systemName: game.state == .live ? "play.fill" : "play.tv.fill")
                    .scaledFont(size: 15, weight: .bold)
                Text(canWatch ? "Watch on \(platform)" : "Broadcast TBA")
                    .scaledFont(size: 17, weight: .semibold)
                if canWatch, let broadcast = activeBroadcast {
                    Text(broadcast)
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(Color(red: 0x5A/255, green: 0x2C/255, blue: 0x06/255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.30)))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(canWatch ? Color.orange : Color.white.opacity(0.15)))
            .shadow(color: canWatch ? Color.orange.opacity(0.55) : .clear, radius: 22, y: 0)
        }
        .buttonStyle(.plain)
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
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            toggleWatchList()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if isSaved {
                        Circle()
                            .fill(Color.clear)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.8))
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
                            .scaledFont(size: 22, weight: .bold)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 56, height: 56)

                Text(isSaved ? "Saved" : "Watch List")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
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
                    platform: activeBroadcast
                )
            }
            await MainActor.run { isToggleSaving = false }
        }
    }

    private var closeButton: some View {
        Button(action: { dismiss() }) {
            HStack(spacing: 6) {
                Text("Close")
                    .scaledFont(size: 15, weight: .semibold)
                Image(systemName: "xmark")
                    .scaledFont(size: 13, weight: .semibold)
            }
            .foregroundStyle(Color.white.opacity(0.85))
        }
        .buttonStyle(.plain)
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
            home: GameTeam(id: nil, uid: nil, abbreviation: "MIA", displayName: "Miami Heat", shortName: "Heat", score: "82", primaryHex: "CE1141", isWinner: false),
            away: GameTeam(id: nil, uid: nil, abbreviation: "NYK", displayName: "New York Knicks", shortName: "Knicks", score: "87", primaryHex: "006BB6", isWinner: true),
            broadcasts: ["ESPN", "TNT"]
        )
    )
    .preferredColorScheme(.dark)
}
