//
//  TeamCrestCircle.swift
//  GuideStreamTV
//
//  Sports restyle (2026-09-25): a team crest on a filled circle with a white
//  ring. The fill is `sports_teams.fill_color` — the team colour, or its
//  secondary colour when the crest is mostly the primary one (computed
//  server-side by the sports_team_fill edge function) — falling back to the
//  ESPN primary colour on the game when the catalogue has no row yet.
//

import SwiftUI

enum SportsCrestStyle {
    /// White ring around every crest circle on the phone. Set from the
    /// approved mockup (3pt). Small circles scale it down — see `ring(for:)`.
    static let ringWidth: CGFloat = 3

    static func ring(for size: CGFloat) -> CGFloat {
        if size >= 44 { return ringWidth }
        if size >= 28 { return ringWidth * 0.67 }
        return max(1, ringWidth * 0.5)
    }

    /// Background of an unselected crest circle (picker tiles not followed).
    static let emptyFill = Color(hex: "141B26")
}

struct TeamCrestCircle: View {
    let team: GameTeam
    let size: CGFloat
    /// False draws the "not followed" state: dark fill and a faint 1.5pt ring.
    var filled: Bool = true
    var ringWidth: CGFloat? = nil

    private var fillHex: String? {
        SportsTeamCatalogService.shared.fillHex(forUid: team.uid) ?? team.primaryHex
    }

    private var fill: Color {
        guard filled else { return SportsCrestStyle.emptyFill }
        return fillHex.map { Color(hex: $0) } ?? Color.white.opacity(0.15)
    }

    var body: some View {
        Circle()
            .fill(fill)
            .overlay { crest.padding(size * 0.18) }
            .overlay {
                Circle().strokeBorder(
                    filled ? Color.white : Color.white.opacity(0.14),
                    lineWidth: filled ? (ringWidth ?? SportsCrestStyle.ring(for: size)) : 1.5
                )
            }
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var crest: some View {
        if let s = team.logoURL, !s.isEmpty, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                case .failure:
                    abbreviation
                default:
                    Color.clear
                }
            }
        } else {
            abbreviation
        }
    }

    private var abbreviation: some View {
        Text(team.abbreviation)
            .font(.system(size: size * 0.26, weight: .heavy))
            .foregroundStyle(filled && Self.isLight(fillHex) ? Color(hex: "0B0F16") : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// True for fills light enough that white text would not read on them.
    static func isLight(_ hex: String?) -> Bool {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return false }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 160
    }
}

// MARK: - Shared Sports card parts (2026-09-25)

/// The one Watch button on every Sports card — hero, Live now and See all.
struct SportsWatchPill: View {
    var body: some View {
        Text("Watch ▶")
            .scaledFont(size: 11, weight: .bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(hex: "F5821F")))
    }
}

/// Card background from `sports_games.image_url` — the ESPN game photo, or
/// the stadium photo the server falls back to — under a dark scrim so the
/// scores stay readable. No URL, or a failed load, keeps the plain card fill.
struct SportsPhotoBackdrop: View {
    let url: String?
    var cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius).fill(Color(hex: "161B27"))
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                            .overlay(
                                LinearGradient(
                                    colors: [Color(hex: "04090F").opacity(0.65), Color(hex: "04090F").opacity(0.88)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    } else {
                        Color.clear
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
    }
}
