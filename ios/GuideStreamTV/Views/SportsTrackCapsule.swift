//
//  SportsTrackCapsule.swift
//  GuideStreamTV
//
//  Live-score tracking capsule, extracted from `SportsWatchSheet` so the watch
//  sheet and the game detail screen share one implementation of the Live
//  Activity toggle instead of drifting apart.
//

import SwiftUI
import UIKit

struct SportsTrackCapsule: View {
    let game: SportsGame
    /// Broadcast handed to the Live Activity when tracking starts. Safe to
    /// pass "" when the game has no broadcasts.
    let broadcast: String

    @State private var liveActivity = SportsLiveActivityController.shared

    /// Whether the live-score capsule should appear at all: Live Activities
    /// enabled AND the game is live or starts within an hour. Exposed so call
    /// sites can gate their own surrounding padding.
    @MainActor
    static func isAvailable(for game: SportsGame) -> Bool {
        guard SportsLiveActivityController.shared.isAvailable else { return false }
        switch game.state {
        case .live:
            return true
        case .pre:
            return game.startDate.timeIntervalSinceNow <= 60 * 60
        case .post:
            return false
        }
    }

    var body: some View {
        if Self.isAvailable(for: game) {
            content
        }
    }

    /// Full-width "track live score" capsule with its 11pt hint. Three
    /// states: idle, tracking this game, another game tracked (switch).
    private var content: some View {
        VStack(spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if isTrackingThisGame {
                    Task { await liveActivity.stop() }
                } else {
                    Task { await liveActivity.start(game: game, broadcast: broadcast) }
                }
            } label: {
                HStack(spacing: 8) {
                    if isTrackingThisGame {
                        LiveActivityPulseDot(color: Color(hex: "F5821F"), size: 7)
                    }
                    Text(capsuleTitle)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(capsuleTextColor)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(capsuleFill))
                .overlay(Capsule().stroke(capsuleBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text(capsuleHint)
                .scaledFont(size: 11)
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let errorText = liveActivity.lastStartError {
                Text(errorText)
                    .scaledFont(size: 11)
                    .foregroundStyle(Color(hex: "FF3B30"))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .onTapGesture {
                        liveActivity.clearLastError()
                    }
            }
        }
    }

    private var isTrackingThisGame: Bool {
        liveActivity.trackedGameId == game.id
    }

    private var isTrackingOtherGame: Bool {
        guard let tracked = liveActivity.trackedGameId else { return false }
        return tracked != game.id
    }

    private var capsuleTitle: String {
        if isTrackingThisGame { return "Tracking · Stop" }
        if isTrackingOtherGame { return "Switch to this game" }
        return "Track live score"
    }

    private var capsuleFill: Color {
        if isTrackingThisGame { return Color(hex: "F5821F").opacity(0.16) }
        if isTrackingOtherGame { return Color(red: 0x5B/255, green: 0xB0/255, blue: 0xFF/255).opacity(0.16) }
        return Color.white.opacity(0.08)
    }

    private var capsuleBorder: Color {
        if isTrackingThisGame { return Color(hex: "F5821F") }
        if isTrackingOtherGame { return Color(red: 0x5B/255, green: 0xB0/255, blue: 0xFF/255) }
        return Color.white.opacity(0.13)
    }

    private var capsuleTextColor: Color {
        if isTrackingThisGame { return Color(hex: "F5821F") }
        if isTrackingOtherGame { return Color(red: 0x5B/255, green: 0xB0/255, blue: 0xFF/255) }
        return .white
    }

    private var capsuleHint: String {
        if isTrackingThisGame { return "Showing in your Dynamic Island. Ends automatically at final." }
        if isTrackingOtherGame { return "Switching ends the game you're currently tracking." }
        return "Live score in your Dynamic Island until the final whistle."
    }
}

/// Small pulsing indicator dot used by the live-score tracking capsule.
struct LiveActivityPulseDot: View {
    let color: Color
    let size: CGFloat
    @State private var pulsing: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(pulsing ? 1.3 : 0.75)
            .opacity(pulsing ? 1.0 : 0.55)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
