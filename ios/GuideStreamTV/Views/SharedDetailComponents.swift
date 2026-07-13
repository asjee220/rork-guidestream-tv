//
//  SharedDetailComponents.swift
//  GuideStreamTV
//
//  Reusable building blocks shared between the TMDB show-detail screen and the
//  creator (YouTube / Twitch / Kick / podcast) detail screen so both render with
//  the same visual structure: full-bleed hero, Fan Activity card, sticky compact
//  header, and the navy / glassmorphism chrome used throughout the app.
//
//  These are pure presentation views — they carry no data-loading logic. The
//  hosting screen supplies the content (image URLs, titles, metadata, button
//  state + actions) so the same components can back entirely different data
//  sources without coupling them.
//

import SwiftUI

// MARK: - Scroll offset preference

/// Drives the sticky compact header on detail screens by reporting the
/// scroll view's vertical offset up through a preference.
struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Grid texture

/// Faint grid overlay that gives the hero gradient subtle depth.
struct GridTexture: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 40
            let color = Color.white.opacity(0.04)
            var x: CGFloat = 0
            while x <= size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(color), lineWidth: 1)
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(color), lineWidth: 1)
                y += spacing
            }
        }
    }
}

// MARK: - Like icon with bounce

/// Heart icon used inside the Fan Activity card; scales up when liked.
struct LikeIcon: View {
    let liked: Bool
    var body: some View {
        Image(systemName: liked ? "heart.fill" : "heart")
            .scaledFont(size: 18, weight: .semibold)
            .foregroundStyle(liked ? Color.orange : .white)
            .scaleEffect(liked ? 1.15 : 1.0)
    }
}

// MARK: - Glass round chrome button

/// Circular glass button used for the hero's back / share chrome.
func detailGlassRoundButton(symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: symbol)
            .scaledFont(size: 15, weight: .semibold)
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(
                Circle()
                    .fill(Color.navy.opacity(0.55))
                    .background(.ultraThinMaterial, in: Circle())
            )
            .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
    .buttonStyle(.plain)
}

private func detailTitleSize(for width: CGFloat) -> CGFloat {
    min(max(width * 0.09, 28), 40)
}

// MARK: - Hero header

/// Full-bleed hero used at the top of both detail screens. The host supplies a
/// background image, a title, and an arbitrary metadata slot (rating/year line
/// for shows, platform/subscriber line for creators).
struct DetailHeroHeader<Metadata: View>: View {
    let heroImageUrl: String?
    let title: String
    @ViewBuilder var metadata: () -> Metadata
    var onBack: () -> Void
    var onShare: () -> Void

    var body: some View {
        GeometryReader { geo in
            let h = min(geo.size.width * 0.56, 280)
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        Color(red: 0x1A/255, green: 0x05/255, blue: 0x33/255),
                        Color(red: 0x0A/255, green: 0x1F/255, blue: 0x52/255),
                        Color.navy
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                GridTexture().opacity(0.4).allowsHitTesting(false)

                if let heroImageUrl, let url = URL(string: heroImageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        default:
                            Color.clear
                        }
                    }
                    .frame(width: geo.size.width, height: h)
                    .clipped()
                    .opacity(0.85)
                    .allowsHitTesting(false)

                    LinearGradient(
                        colors: [Color.navy.opacity(0.25), .clear, Color.navy],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }

                LinearGradient(
                    colors: [.clear, Color.navy],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: h * 0.55)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                // Top chrome
                HStack {
                    detailGlassRoundButton(symbol: "arrow.left", action: onBack)
                    Spacer()
                    detailGlassRoundButton(symbol: "square.and.arrow.up", action: onShare)
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)

                // Title block
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .scaledFont(size: detailTitleSize(for: geo.size.width), weight: .semibold, design: .default)
                        .foregroundStyle(.white)
                    metadata()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .frame(width: geo.size.width, height: h)
            .clipped()
        }
        .frame(height: min(UIScreen.main.bounds.width * 0.56, 280))
    }
}

// MARK: - Social counter row

/// Shared like / comment counter row used by every detail surface (episode
/// sheet, show detail, creator detail). Renders a heart button with the like
/// count and a comment button with the comment count, both driven by
/// `SocialViewModel` through the host's closures so counts and fill state stay
/// in sync with the real `title_likes` / `title_comments` tables.
struct SocialCounterRow: View {
    let titleId: String
    var isLiked: Bool
    var likeCount: Int
    var commentCount: Int
    var onLike: () -> Void
    var onComment: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onLike) {
                HStack(spacing: 7) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .scaledFont(size: 20)
                        .foregroundStyle(Color.orange)
                    Text(formatCount(likeCount))
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Like")

            Text("·")
                .scaledFont(size: 13)
                .foregroundStyle(Color.white.opacity(0.4))

            Button(action: onComment) {
                HStack(spacing: 7) {
                    Image(systemName: "bubble.left")
                        .scaledFont(size: 20)
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text(formatCount(commentCount))
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comments")

            Spacer(minLength: 0)
        }
    }

    /// Compact count formatting matching the rest of the app:
    /// 0 -> "0", 1234 -> "1.2K", 1_234_567 -> "1.2M".
    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Fan Activity card

/// "Fan Activity" card with two circular action buttons (save, notify). Each
/// button's state and action is supplied by the host so the same card can drive
/// a TMDB title's watchlist paths or a creator's follow/notify paths. Like and
/// comment now live in `SocialCounterRow` on every surface.
struct FanActivityCard: View {
    let isSaved: Bool
    let saveLabel: String
    let onSave: () -> Void
    let notifyOn: Bool
    let onNotify: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fan Activity")
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                fanButton(label: saveLabel) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(isSaved ? Color.orange : .white)
                } action: {
                    onSave()
                }

                fanButton(label: "Notify", showDot: notifyOn) {
                    Image(systemName: notifyOn ? "bell.fill" : "bell")
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(.white)
                } action: {
                    onNotify()
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    @ViewBuilder
    private func fanButton<Icon: View>(
        label: String,
        filled: Bool = false,
        showDot: Bool = false,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                icon()
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if showDot {
                            Circle()
                                .fill(Color(red: 0.20, green: 0.78, blue: 0.35))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.navy, lineWidth: 2))
                                .offset(x: 2, y: -2)
                        }
                    }
            }
            .buttonStyle(.plain)

            Text(label)
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Service badge

/// Streaming-service chip used in the "Where to Watch" rows on both detail
/// surfaces. Shows a color dot, the service name, an optional green
/// "Subscribed" badge, and — when `isSelected` — a service-color ring plus a
/// small orange checkmark marking it as the active source the Watch button
/// follows.
struct ServiceBadge: View {
    let name: String
    let color: Color
    var isSubscribed: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(gsDisplayName(for: name))
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(.white)
            if isSubscribed {
                Text("Subscribed")
                    .scaledFont(size: 9, weight: .heavy)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.green.opacity(0.85))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSubscribed ? color.opacity(0.28) : color.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected ? color : (isSubscribed ? color.opacity(0.70) : color.opacity(0.45)),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .padding(.top, 8)
        .padding(.trailing, 8)
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark")
                    .scaledFont(size: 9, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.orange))
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 0.5))
            }
        }
    }
}

// MARK: - Sticky compact header

/// Sticky condensed header that fades in as the user scrolls past the hero.
/// The host supplies the title, a back action, and an optional trailing slot
/// (e.g. a "Play on" button for shows or a share button for creators).
struct DetailCompactHeader<Trailing: View>: View {
    let title: String
    var onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            Color.navy.opacity(0.85)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }

            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
                Text(title)
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)

                trailing()
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
