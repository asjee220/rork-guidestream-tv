//
//  HomeDestinations.swift
//  GuideStreamTV
//

import SwiftUI

enum HomeRoute: Hashable {
    case newEpisodes
    case widgetSetup
}

enum DetailSubject: Identifiable, Hashable {
    case episode(Episode)
    case show(PosterShow)

    var id: String {
        switch self {
        case .episode(let e): return "ep-\(e.id.uuidString)"
        case .show(let s): return "sh-\(s.id.uuidString)"
        }
    }
}

// MARK: - Episode Detail Sheet

struct EpisodeDetailSheet: View {
    let subject: DetailSubject
    @Environment(\.dismiss) private var dismiss

    @State private var resolvedBackdrop: String?
    @State private var isLiked: Bool = false
    @State private var isNotifying: Bool = true
    @State private var showCastSheet: Bool = false

    private var platformColor: Color {
        switch subject {
        case .episode(let e): return e.platformColor
        case .show(let s): return s.posterColors.first ?? Color(red: 0x6A/255, green: 0x3F/255, blue: 0xE0/255)
        }
    }

    private var platformName: String {
        switch subject {
        case .episode(let e): return e.platform
        case .show: return "HBO MAX"
        }
    }

    private var whereToWatchLabel: String {
        switch subject {
        case .episode(let e): return e.platform.capitalized
        case .show: return "HBO Max"
        }
    }

    private var aboutText: String {
        "Four adult children of a media mogul compete for control of their father's empire as his health fails. One of the greatest dramas ever made."
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

                viewFullDetailsButton
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color(red: 0x06/255, green: 0x0C/255, blue: 0x18/255).ignoresSafeArea())
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .sheet(isPresented: $showCastSheet) {
            CastToTVSheet(
                isPresented: $showCastSheet,
                showTitle: title,
                platform: whereToWatchLabel,
                tmdbId: tmdbId
            )
        }
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 16) {
            posterThumbnail
                .frame(width: 110, height: 150)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(meta)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))

                HStack(spacing: 8) {
                    Text(platformName.uppercased())
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(platformColor))

                    Text("Drama")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .padding(.top, 2)

                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0xFF/255, green: 0xC4/255, blue: 0x3D/255))
                    }
                    Text("9.6")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.leading, 4)
                }
                .padding(.top, 2)

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.orange)
                        Text("2.4K")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Likes")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Text("·")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.4))
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.7))
                        Text("183")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Comments")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
    }

    private var posterThumbnail: some View {
        Color.black
            .overlay {
                RemoteImage(
                    urlString: posterUrl,
                    contentMode: .fill,
                    fallbackColors: colors
                )
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                Text(String(platformName.prefix(4)).uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(platformColor))
                    .padding(8)
            }
    }

    // MARK: - Actions row

    private var actionsRow: some View {
        HStack(spacing: 0) {
            circleAction(icon: isLiked ? "heart.fill" : "heart", label: "Like", tint: isLiked ? Color.orange : .white, showDot: false) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isLiked.toggle() }
            }
            .frame(maxWidth: .infinity)

            circleAction(icon: "bell.fill", label: "Notify", tint: .white, showDot: isNotifying) {
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
                        .font(.system(size: 22, weight: .regular))
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
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ABOUT")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(aboutText)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Where to watch

    private var whereToWatchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHERE TO WATCH")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.45))

            HStack(spacing: 10) {
                Text(whereToWatchLabel)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(platformColor))
            }

            Text("Available with subscription")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - CTA

    private var watchButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            StreamingDeepLinker.open(
                platform: whereToWatchLabel,
                title: title,
                tmdbId: tmdbId,
                isTV: { if case .show = subject { return true } else { return true } }()
            )
            dismiss()
        } label: {
            Text("Watch on \(whereToWatchLabel)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(Color.orange))
                .shadow(color: Color.orange.opacity(0.55), radius: 22, y: 0)
        }
        .buttonStyle(.plain)
    }

    private var viewFullDetailsButton: some View {
        Button(action: { dismiss() }) {
            HStack(spacing: 6) {
                Text("View Full Details")
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        switch subject {
        case .episode(let e): return e.title
        case .show(let s): return s.title
        }
    }

    private var meta: String {
        switch subject {
        case .episode(let e): return "\(e.season) · \(e.duration) · \(e.platform)"
        case .show(let s): return s.meta
        }
    }

    private var colors: [Color] {
        switch subject {
        case .episode(let e): return e.posterColors
        case .show(let s): return s.posterColors
        }
    }

    private var symbol: String {
        switch subject {
        case .episode(let e): return e.symbol
        case .show(let s): return s.symbol
        }
    }

    /// Prefer the real TMDB still/poster; we also resolve a backdrop lazily by tmdbId for a richer hero.
    private var posterUrl: String? {
        switch subject {
        case .episode(let e): return e.posterUrl
        case .show(let s): return s.posterUrl
        }
    }

    private var tmdbId: Int? {
        switch subject {
        case .episode(let e): return e.tmdbId
        case .show(let s): return s.tmdbId
        }
    }

}

// MARK: - New Episodes List

struct NewEpisodesListView: View {
    let episodes: [Episode]
    var onSelect: (Episode) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(episodes) { ep in
                    Button(action: { onSelect(ep) }) {
                        EpisodeRow(episode: ep)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(Color.navy.ignoresSafeArea())
        .navigationTitle("New Episodes")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct EpisodeRow: View {
    let episode: Episode

    var body: some View {
        HStack(spacing: 14) {
            Color.black
                .frame(width: 120, height: 72)
                .overlay {
                    RemoteImage(
                        urlString: episode.posterUrl,
                        contentMode: .fill,
                        fallbackColors: episode.posterColors
                    )
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(episode.platform)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(episode.platformColor))
                    if episode.isNew {
                        Text("NEW")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange))
                    }
                }
                Text(episode.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(episode.season) · \(episode.duration)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(10)
        .background(
            Color.white.opacity(0.05)
                .background(.ultraThinMaterial)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(.rect(cornerRadius: 12))
    }
}

// MARK: - Widget Setup

struct WidgetSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0xFF/255, green: 0x9A/255, blue: 0x3C/255),
                                Color(red: 0xE6/255, green: 0x72/255, blue: 0x1A/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("UP NEXT")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Stranger Things")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                            Text("S5 E1 · 64min")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(16)
                    }
                    .shadow(color: Color.orange.opacity(0.4), radius: 24, y: 10)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 14) {
                    StepRow(number: 1, title: "Long press your home screen", subtitle: "Until apps start jiggling.")
                    StepRow(number: 2, title: "Tap the + button", subtitle: "In the top-left corner.")
                    StepRow(number: 3, title: "Search \"GuideStream\"", subtitle: "Pick a small, medium, or large widget.")
                    StepRow(number: 4, title: "Add Widget", subtitle: "Drop it anywhere on your home screen.")
                }
                .padding(.horizontal, 20)

                Button(action: { dismiss() }) {
                    Text("Got it")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(Color.orange))
                        .shadow(color: Color.orange.opacity(0.5), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 40)
            }
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background(Color.navy.ignoresSafeArea())
        .navigationTitle("Set Up Widget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.orange)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.orange.opacity(0.14)))
                .overlay(Circle().stroke(Color.orange.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Notifications Sheet

struct NotificationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var streams = StreamsViewModel.shared
    @State private var trendingFallback: [TMDBResult] = []

    private var liveItems: [NotificationDisplayItem] {
        if !streams.newEpisodes.isEmpty {
            return streams.newEpisodes.prefix(50).map { row in
                NotificationDisplayItem(
                    id: row.id,
                    title: row.title ?? "New episode",
                    subtitle: subtitle(for: row),
                    time: relativeTime(row.releasedAt),
                    posterUrl: row.posterUrl,
                    titleId: row.titleId,
                    platformId: row.platform?.lowercased() ?? "",
                    type: "new_episode",
                    badge: "NEW"
                )
            }
        }
        return trendingFallback.prefix(20).map { r in
            NotificationDisplayItem(
                id: "tmdb-\(r.id)",
                title: r.displayName,
                subtitle: r.overview ?? "Trending on streaming this week.",
                time: r.year.map { "\($0)" } ?? "Trending",
                posterUrl: r.posterUrl,
                titleId: String(r.id),
                platformId: "tmdb",
                type: "trending",
                badge: "TRENDING"
            )
        }
    }

    private func subtitle(for row: NewEpisodeRow) -> String {
        let s = row.season ?? 1
        let e = row.episode ?? 1
        let platform = row.platform ?? ""
        if platform.isEmpty { return "S\(s) E\(e)" }
        return "S\(s) E\(e) · \(platform)"
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Notifications")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if liveItems.isEmpty {
                        Text("You're all caught up.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(liveItems) { item in
                            Button {
                                WatchIntentLogger.shared.log(
                                    eventType: .notificationOpened,
                                    titleId: item.titleId,
                                    platformId: item.platformId,
                                    metadata: ["notification_type": item.type]
                                )
                            } label: {
                                NotificationRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.navy.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .task {
            await streams.refreshAll()
            if streams.newEpisodes.isEmpty,
               let results = try? await TMDBService.shared.getTrending() {
                trendingFallback = results
            }
        }
    }
}

struct NotificationDisplayItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let time: String
    let posterUrl: String?
    let titleId: String
    let platformId: String
    let type: String
    let badge: String
}

private struct NotificationRow: View {
    let item: NotificationDisplayItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Color.black
                .frame(width: 56, height: 80)
                .overlay {
                    RemoteImage(urlString: item.posterUrl, contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    Text(item.badge)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.orange)
                        )
                        .padding(4)
                }
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(item.time)
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(.rect(cornerRadius: 12))
    }
}
