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

    @State private var isReminderSet: Bool = false
    @State private var isNotifying: Bool = false
    @State private var showCastSheet: Bool = false

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

                aboutSection
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                whereToWatchSection
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                watchButton
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                closeButton
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color(red: 0x06/255, green: 0x0C/255, blue: 0x18/255).ignoresSafeArea())
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .sheet(isPresented: $showCastSheet) {
            CastToTVSheet(
                isPresented: $showCastSheet,
                showTitle: gameTitle,
                platform: primaryBroadcast ?? "",
                tmdbId: nil,
                isTV: false
            )
        }
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
        HStack(spacing: 0) {
            circleAction(
                icon: isReminderSet ? "bell.badge.fill" : "alarm",
                label: "Remind me",
                tint: isReminderSet ? Color.orange : .white,
                showDot: isReminderSet
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isReminderSet.toggle() }
            }
            .frame(maxWidth: .infinity)

            circleAction(
                icon: "bell.fill",
                label: "Notify",
                tint: .white,
                showDot: isNotifying
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isNotifying.toggle() }
            }
            .frame(maxWidth: .infinity)

            circleAction(icon: "tv", label: "Send to TV", tint: .white, showDot: false) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showCastSheet = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func circleAction(icon: String, label: String, tint: Color, showDot: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
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
                            .overlay(Circle().stroke(Color(red: 0x06/255, green: 0x0C/255, blue: 0x18/255), lineWidth: 2))
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

    // MARK: - Where to watch

    private var whereToWatchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHERE TO WATCH")
                .scaledFont(size: 12, weight: .heavy)
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.45))

            if game.broadcasts.isEmpty {
                Text("Broadcast not announced yet — check back closer to game time.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.5))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(game.broadcasts, id: \.self) { name in
                            broadcastChip(name)
                        }
                    }
                }
                .scrollClipDisabled()
            }

            if !game.broadcasts.isEmpty {
                Text(availabilityLabel)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var availabilityLabel: String {
        switch game.state {
        case .live: return "Streaming live now"
        case .pre: return "Coverage starts at \(formattedStartLocal)"
        case .post: return "Highlights and replay available"
        }
    }

    private func broadcastChip(_ name: String) -> some View {
        Text(name)
            .scaledFont(size: 13, weight: .heavy)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
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

    private var watchButton: some View {
        let platform = primaryBroadcast ?? ""
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
            home: GameTeam(abbreviation: "MIA", displayName: "Miami Heat", shortName: "Heat", score: "82", primaryHex: "CE1141", isWinner: false),
            away: GameTeam(abbreviation: "NYK", displayName: "New York Knicks", shortName: "Knicks", score: "87", primaryHex: "006BB6", isWinner: true),
            broadcasts: ["ESPN", "TNT"]
        )
    )
    .preferredColorScheme(.dark)
}
