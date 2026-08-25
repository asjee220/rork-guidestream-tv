//
//  SportsLiveActivity.swift
//  GuideStreamWidget
//
//  Live Activity for live sports scores — Dynamic Island + Lock Screen.
//  Score updates arrive via ActivityKit push (ContentState matches the
//  server payload). Live Activities cannot load remote images, so team
//  crests are local rounded rects tinted with each team's brand hex.
//

import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

// MARK: - Colors

private let liveNavy = Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255)
private let brandOrange = Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255)
private let liveOrange = Color(red: 0xFF/255, green: 0x9F/255, blue: 0x0A/255)
private let liveRed = Color(red: 0xFF/255, green: 0x3B/255, blue: 0x30/255)
private let mutedGrey = Color.white.opacity(0.55)

/// Team brand colour from a hex string, reusing the widget target's
/// existing failable `Color(hex:)` with a brand-orange fallback.
private func liveTeamColor(_ hex: String) -> Color {
    Color(hex: hex) ?? brandOrange
}

/// Deep link back into the Sports tab for this game.
private func gameDeepLinkURL(_ gameId: String) -> URL? {
    URL(string: "guidestream://game/\(gameId)")
}

// MARK: - Shared pieces

private struct TeamCrest: View {
    let abbr: String
    let hex: String
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(liveTeamColor(hex))
            .frame(width: size, height: size)
            .overlay {
                Text(abbr)
                    .font(.system(size: size * 0.36, weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
    }
}

private struct LivePulseDot: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .modifier(PulsingDot())
    }
}

private struct LeagueChip: View {
    let leagueShort: String
    /// Defaults to the Dynamic Island's size. The lock screen passes a larger
    /// value — it has the room, the Island does not.
    var fontSize: CGFloat = 8.5

    var body: some View {
        Text(leagueShort.uppercased())
            .font(.system(size: fontSize, weight: .bold).monospaced())
            .tracking(0.6)
            .foregroundStyle(Color.white.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.10)))
    }
}

private struct SplitAccentBar: View {
    let awayHex: String
    let homeHex: String

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(liveTeamColor(awayHex))
            Rectangle().fill(liveTeamColor(homeHex))
        }
        .frame(height: 3)
    }
}

private struct WatchButtonLabel: View {
    let broadcast: String
    /// Defaults to the Dynamic Island's sizing. The lock screen passes larger
    /// values; the Island's bottom region is too tight for them.
    var fontSize: CGFloat = 13
    var height: CGFloat = 36

    var body: some View {
        Text(broadcast.isEmpty ? "Watch now" : "Watch on \(broadcast)")
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(brandOrange))
    }
}

// MARK: - Widget

struct SportsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SportsActivityAttributes.self) { context in
            LockScreenSportsView(context: context)
                .widgetURL(URL(string: "guidestream://game/\(context.attributes.gameId)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        TeamCrest(
                            abbr: context.attributes.awayAbbr,
                            hex: context.attributes.awayHex,
                            size: 26
                        )
                        Text("\(context.state.awayScore)")
                            .font(.system(size: 32, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 6) {
                        Text("\(context.state.homeScore)")
                            .font(.system(size: 32, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white)
                        TeamCrest(
                            abbr: context.attributes.homeAbbr,
                            hex: context.attributes.homeHex,
                            size: 26
                        )
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        HStack(spacing: 5) {
                            if context.state.state == "live" {
                                LivePulseDot(color: liveOrange, size: 6)
                            }
                            Text(context.state.statusDetail)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(context.state.state == "live" ? liveOrange : mutedGrey)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        LeagueChip(leagueShort: context.attributes.leagueShort)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        SplitAccentBar(
                            awayHex: context.attributes.awayHex,
                            homeHex: context.attributes.homeHex
                        )
                        if let url = gameDeepLinkURL(context.attributes.gameId) {
                            Link(destination: url) {
                                WatchButtonLabel(broadcast: context.attributes.broadcast)
                            }
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    if context.state.state == "live" {
                        LivePulseDot(color: liveRed, size: 6)
                    }
                    TeamCrest(
                        abbr: context.attributes.awayAbbr,
                        hex: context.attributes.awayHex,
                        size: 20
                    )
                    Text("\(context.state.awayScore)")
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            } compactTrailing: {
                HStack(spacing: 4) {
                    Text("\(context.state.homeScore)")
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                    TeamCrest(
                        abbr: context.attributes.homeAbbr,
                        hex: context.attributes.homeHex,
                        size: 20
                    )
                }
            } minimal: {
                let awayLeads = context.state.awayScore > context.state.homeScore
                HStack(spacing: 4) {
                    TeamCrest(
                        abbr: awayLeads ? context.attributes.awayAbbr : context.attributes.homeAbbr,
                        hex: awayLeads ? context.attributes.awayHex : context.attributes.homeHex,
                        size: 18
                    )
                    Text("\(awayLeads ? context.state.awayScore : context.state.homeScore)")
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - Lock Screen / banner view

private struct LockScreenSportsView: View {
    let context: ActivityViewContext<SportsActivityAttributes>

    private var isLive: Bool { context.state.state == "live" }

    var body: some View {
        VStack(spacing: 8) {
            SplitAccentBar(
                awayHex: context.attributes.awayHex,
                homeHex: context.attributes.homeHex
            )

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(brandOrange)
                    .frame(width: 16, height: 16)
                    .overlay {
                        Text("G")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                Text("GuideStream · \(context.attributes.leagueShort)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
            }

            scoreboardRow(
                abbr: context.attributes.awayAbbr,
                hex: context.attributes.awayHex,
                shortName: context.attributes.awayShortName,
                score: context.state.awayScore
            )
            scoreboardRow(
                abbr: context.attributes.homeAbbr,
                hex: context.attributes.homeHex,
                shortName: context.attributes.homeShortName,
                score: context.state.homeScore
            )

            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    if isLive {
                        LivePulseDot(color: liveOrange, size: 6)
                    }
                    Text(context.state.statusDetail)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isLive ? liveOrange : mutedGrey)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                LeagueChip(leagueShort: context.attributes.leagueShort, fontSize: 10.5)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)

            WatchButtonLabel(
                broadcast: context.attributes.broadcast,
                fontSize: 15,
                height: 38
            )
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(liveNavy)
        .clipShape(.rect(cornerRadius: 14))
    }

    private func scoreboardRow(abbr: String, hex: String, shortName: String, score: Int) -> some View {
        HStack(spacing: 8) {
            TeamCrest(abbr: abbr, hex: hex, size: 25)
            Text(shortName)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Text("\(score)")
                .font(.system(size: 32, weight: .heavy).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}
