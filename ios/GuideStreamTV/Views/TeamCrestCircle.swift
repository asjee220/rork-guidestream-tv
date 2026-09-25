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
