//
//  TVTeamCrestCircle.swift
//  GuideStreamTVTV
//
//  Sports restyle (2026-09-25): a team crest on a filled circle with a white
//  ring — the tvOS twin of the phone's TeamCrestCircle. The fill is
//  `sports_teams.fill_color` (primary, or secondary when the crest is mostly
//  the primary colour), falling back to the game's ESPN primary colour.
//
//  Focus is the crest's own ring getting thicker plus a small lift, drawn by
//  the caller through `focused` — never tvOS's white focus slab.
//

import SwiftUI

enum TVSportsCrestStyle {
    /// White ring around every crest circle on Apple TV. Set from the
    /// approved mockup (4pt). Small circles scale it down.
    static let ringWidth: CGFloat = 4

    static func ring(for size: CGFloat) -> CGFloat {
        if size >= 90 { return ringWidth }
        if size >= 50 { return ringWidth * 0.75 }
        return max(1.5, ringWidth * 0.5)
    }

    static let emptyFill = Color(hex: "141B26")
}

struct TVTeamCrestCircle: View {
    let team: TVGameTeam
    let size: CGFloat
    /// False draws the "not followed" state: dark fill and a faint ring.
    var filled: Bool = true
    var focused: Bool = false

    private var fillHex: String? {
        TVSportsTeamCatalogService.shared.fillHex(forUid: team.uid) ?? team.primaryHex
    }

    private var ring: CGFloat {
        let base = filled ? TVSportsCrestStyle.ring(for: size) : 2
        return focused ? base + 2 : base
    }

    private var ringColor: Color {
        (filled || focused) ? .white : Color.white.opacity(0.14)
    }

    var body: some View {
        Circle()
            .fill(filled ? (fillHex.map { Color(hex: $0) } ?? Color.white.opacity(0.15)) : TVSportsCrestStyle.emptyFill)
            .overlay { crest.padding(size * 0.18) }
            .overlay { Circle().strokeBorder(ringColor, lineWidth: ring) }
            .frame(width: size, height: size)
            .scaleEffect(focused ? 1.08 : 1)
            .shadow(color: .black.opacity(focused ? 0.6 : 0), radius: focused ? 18 : 0, y: focused ? 12 : 0)
            .animation(.easeOut(duration: 0.15), value: focused)
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
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
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

    static func isLight(_ hex: String?) -> Bool {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return false }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 160
    }
}

// MARK: - Shared Sports card parts (2026-09-25)

/// The one Watch button on every Apple TV Sports card — hero, Live now and
/// See all. Twin of the phone's SportsWatchPill at TV scale.
struct TVSportsWatchPill: View {
    var body: some View {
        Text("Watch ▶")
            .scaledFont(size: 26, weight: .bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color(hex: "F5821F")))
    }
}

/// Card background from `sports_games.image_url` — the ESPN game photo, or
/// the stadium photo the server falls back to — under a dark scrim. No URL,
/// or a failed load, keeps the plain card fill.
struct TVSportsPhotoBackdrop: View {
    let url: String?
    var cornerRadius: CGFloat = 16

    // The card's size comes from the rounded rectangle alone. The photo is an
    // overlay, which is proposed exactly that size, fills it, and is clipped
    // with it — a scaledToFill image as the background's own content reported
    // the photo's size instead and spilled over the neighbouring cards.
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(hex: "161B27"))
            .overlay {
                if let s = url, let u = URL(string: s) {
                    AsyncImage(url: u) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .overlay(
                                    // Same scrim as the My games cards, so a
                                    // photo is equally bright in both sections.
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color(hex: "04090F").opacity(0.05), location: 0),
                                            .init(color: Color(hex: "04090F").opacity(0.30), location: 0.45),
                                            .init(color: Color(hex: "04090F").opacity(0.90), location: 1)
                                        ],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                        } else {
                            Color.clear
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
