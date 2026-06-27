//
//  PlayOnBottomSheet.swift
//  GuideStreamTV
//

import SwiftUI
import UIKit

enum PlayOnDeviceType {
    case iphone
    case appleTv
    case tv
}

struct PlayOnDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let sublabel: String
    let type: PlayOnDeviceType
}

enum PlayOnRowState: Equatable {
    case `default`
    case selected
    case connecting
}

struct PlayOnBottomSheet: View {
    let isOpen: Bool
    let onClose: () -> Void
    let showTitle: String
    let showSubtitle: String
    let thumbnailUrl: String?
    var tmdbId: Int? = nil
    var isTV: Bool = true
    var initialSelectedDevice: String = "living-room"
    let onDeviceSelected: (String) -> Void

    // Illustrative metadata used until the live Watchmode lookup resolves
    // (or as a fallback when the API is unavailable). Anything tied to the
    // streaming service — platform name, color, deeplink — is replaced with
    // the real source as soon as we have it.
    private let yearsLabel: String = "2018–2023 · 4 Seasons · TV-MA"
    private let genreLabel: String = "Drama"
    private let rating: Double = 9.6
    private let likeCount: String = "2.4K"
    private let commentCount: String = "183"
    private let fallbackAboutText: String = "Tap the watch button to open this title in the streaming app."
    private let availabilityLabel: String = "Available with subscription"
    private let watchCTAColor: Color = Color.orange

    @State private var isLiked: Bool = false
    @State private var isNotifying: Bool = true
    @State private var showCastSheet: Bool = false
    /// Watchmode-resolved source for this title. When present, drives the
    /// platform label, brand color, and the watch CTA deeplink.
    @State private var resolvedSource: WatchmodeSource?
    @State private var resolvedOverview: String?
    @State private var isResolvingSource: Bool = false

    private var resolvedPlatformName: String {
        let raw = resolvedSource?.name ?? (isResolvingSource ? "…" : "Streaming")
        return raw == "…" || raw == "Streaming" ? raw : gsDisplayName(for: raw)
    }

    /// Maps Watchmode's raw source names to the user-facing brand labels
    /// used everywhere else in the app. Mirrors the iOS `EpisodeAvailabilitySection`
    /// helper so this tvOS-only file doesn't depend on iOS source files.
    private func gsDisplayName(for raw: String) -> String {
        let k = raw.lowercased()
        if k.contains("paramount") {
            if k.contains("plus") || k.contains("+") { return "Paramount+" }
            return "Paramount+"
        }
        if k.contains("disney") {
            if k.contains("plus") || k.contains("+") { return "Disney+" }
            return "Disney+"
        }
        if k.contains("apple") && (k.contains("tv") || k.contains("+")) { return "Apple TV+" }
        if k.contains("max") || (k.contains("hbo") && k.contains("max")) { return "Max" }
        if k.contains("prime") || (k.contains("amazon") && k.contains("prime")) { return "Prime Video" }
        if k.contains("peacock") { return "Peacock" }
        if k.contains("crunchyroll") { return "Crunchyroll" }
        if k.contains("showtime") { return "Showtime" }
        return raw
    }

    private var platformLabel: String { resolvedPlatformName.uppercased() }

    private var whereToWatchLabel: String {
        if let name = resolvedSource?.name { return gsDisplayName(for: name) }
        return isResolvingSource ? "Finding service\u2026" : "Open streaming app"
    }

    private var platformColor: Color { brandColor(for: resolvedPlatformName) }

    private var aboutText: String { resolvedOverview ?? fallbackAboutText }

    private func brandColor(for name: String) -> Color {
        let key = name.lowercased()
        if key.contains("netflix") { return Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255) }
        if key.contains("hbo") || key.contains("max") { return Color(red: 0x5B/255, green: 0x2D/255, blue: 0x8E/255) }
        if key.contains("hulu") { return Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255) }
        if key.contains("disney") { return Color(red: 0.05, green: 0.10, blue: 0.42) }
        if key.contains("apple") { return Color(white: 0.12) }
        if key.contains("prime") || key.contains("amazon") { return Color(red: 0.0, green: 0.66, blue: 0.93) }
        if key.contains("paramount") { return Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255) }
        if key.contains("peacock") { return Color(red: 0.05, green: 0.05, blue: 0.10) }
        if key.contains("youtube") { return Color(red: 0.90, green: 0.10, blue: 0.10) }
        if key.contains("crunchyroll") { return Color(red: 0xF4/255, green: 0x7B/255, blue: 0x20/255) }
        if key.contains("showtime") { return Color(red: 0xD8/255, green: 0x00/255, blue: 0x00/255) }
        if key.contains("starz") { return Color(white: 0.08) }
        return Color(red: 0x6A/255, green: 0x3F/255, blue: 0xE0/255)
    }

    /// `true` once Watchmode tells us the format is a movie. Used to forward
    /// the correct `MediaType` to Roku ECP and to drive the right Watchmode
    /// search field (`tmdb_movie_id` vs `tmdb_tv_id`).
    private var resolvedIsTV: Bool {
        if let fmt = resolvedSource?.format?.lowercased() {
            return fmt.contains("tv") || fmt.contains("series")
        }
        return isTV
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(isOpen ? 0.55 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(isOpen)
                    .onTapGesture { close() }
                    .animation(.easeOut(duration: 0.2), value: isOpen)

                sheetContent(maxHeight: geo.size.height * 0.86)
                    .offset(y: isOpen ? 0 : geo.size.height)
                    .animation(.interpolatingSpring(stiffness: 280, damping: 26), value: isOpen)
            }
            .ignoresSafeArea()
        }
        #if os(tvOS)
        .fullScreenCover(isPresented: $showCastSheet) {
            CastToTVSheet(
                isPresented: $showCastSheet,
                showTitle: showTitle,
                platform: whereToWatchLabel,
                tmdbId: tmdbId,
                isTV: resolvedIsTV
            )
        }
        #else
        .sheet(isPresented: $showCastSheet) {
            CastToTVSheet(
                isPresented: $showCastSheet,
                showTitle: showTitle,
                platform: whereToWatchLabel,
                tmdbId: tmdbId,
                isTV: resolvedIsTV
            )
        }
        #endif
        .task(id: tmdbId ?? -1) {
            await resolveStreamingSource()
        }
    }

    /// Resolves the title's actual streaming service via Watchmode so the
    /// sheet displays the correct platform and the watch CTA opens the right
    /// app to the right title.
    private func resolveStreamingSource() async {
        guard let tmdbId, resolvedSource == nil, !isResolvingSource else { return }
        isResolvingSource = true
        defer { isResolvingSource = false }
        do {
            guard let watchmodeId = try await WatchmodeService.shared.watchmodeId(forTMDBId: tmdbId, isTV: isTV) else { return }
            let detail = try await WatchmodeService.shared.titleDetail(titleId: watchmodeId)
            await MainActor.run { self.resolvedOverview = detail.plotOverview }
            guard let sources = detail.sources, !sources.isEmpty else { return }
            let ranked = sources.sorted { a, b in sourceRank(a) < sourceRank(b) }
            if let chosen = ranked.first {
                await MainActor.run { self.resolvedSource = chosen }
            }
        } catch {
            #if DEBUG
            print("[PlayOnBottomSheet] Watchmode lookup failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func sourceRank(_ s: WatchmodeSource) -> Int {
        switch s.type.lowercased() {
        case "sub": return 0
        case "free": return 1
        case "tve": return 2
        case "rent": return 3
        case "purchase", "buy": return 4
        default: return 5
        }
    }

    private func close() { onClose() }

    // MARK: - Sheet body

    private func sheetContent(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 44, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                        .padding(.horizontal, 20)
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
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: maxHeight, alignment: .top)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 28, topTrailing: 28), style: .continuous)
                .fill(Color(red: 0x06/255, green: 0x0C/255, blue: 0x18/255))
        )
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 28, topTrailing: 28), style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 28, y: -10)
    }

    // MARK: - Header row (poster + meta)

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 16) {
            posterThumbnail
                .frame(width: 110, height: 150)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text(showTitle)
                    .scaledFont(size: 26, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(yearsLabel)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.55))

                HStack(spacing: 8) {
                    Text(platformLabel)
                        .scaledFont(size: 11, weight: .heavy)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(platformColor))

                    Text(genreLabel)
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .padding(.top, 2)

                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .scaledFont(size: 11)
                            .foregroundStyle(Color(red: 0xFF/255, green: 0xC4/255, blue: 0x3D/255))
                    }
                    Text(String(format: "%.1f", rating))
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.leading, 4)
                }
                .padding(.top, 2)

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.orange)
                        Text(likeCount)
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(.white)
                        Text("Likes")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Text("·")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.4))
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.white.opacity(0.7))
                        Text(commentCount)
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(.white)
                        Text("Comments")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
    }

    private var posterThumbnail: some View {
        ZStack {
            if let urlString = thumbnailUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        posterFallback
                    }
                }
            } else {
                posterFallback
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(String(resolvedPlatformName.prefix(4)).uppercased())
                .scaledFont(size: 10, weight: .heavy)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(platformColor))
                .padding(8)
        }
    }

    private var posterFallback: some View {
        LinearGradient(
            colors: [
                Color(red: 0xB8/255, green: 0x86/255, blue: 0x2C/255),
                Color(red: 0x6A/255, green: 0x4A/255, blue: 0x10/255)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Actions row

    private var actionsRow: some View {
        HStack(spacing: 0) {
            actionButton(
                icon: isLiked ? "heart.fill" : "heart",
                label: "Like",
                tint: isLiked ? Color.orange : .white,
                showDot: false
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isLiked.toggle() }
            }
            .frame(maxWidth: .infinity)

            actionButton(
                icon: "bell.fill",
                label: "Notify",
                tint: .white,
                showDot: isNotifying
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isNotifying.toggle() }
            }
            .frame(maxWidth: .infinity)

            actionButton(
                icon: "tv",
                label: "Send to TV",
                tint: .white,
                showDot: false
            ) {
                showCastSheet = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func actionButton(icon: String, label: String, tint: Color, showDot: Bool, action: @escaping () -> Void) -> some View {
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

            HStack(spacing: 10) {
                Text(whereToWatchLabel)
                    .scaledFont(size: 13, weight: .heavy)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(platformColor))
            }

            Text(availabilityLabel)
                .scaledFont(size: 13)
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - CTA

    private var watchButton: some View {
        Button {
            WatchIntentLogger.shared.log(
                eventType: .playOnDeviceChosen,
                titleId: WatchIntentLogger.titleSlug(showTitle),
                metadata: ["device_id": "watch-on-platform", "platform": whereToWatchLabel]
            )
            StreamingDeepLinker.open(
                platform: whereToWatchLabel,
                title: showTitle,
                tmdbId: tmdbId,
                isTV: resolvedIsTV
            )
            onDeviceSelected("watch-on-platform")
        } label: {
            HStack(spacing: 8) {
                if isResolvingSource && resolvedSource == nil {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(resolvedSource == nil && isResolvingSource
                     ? "Finding service…"
                     : "Watch on \(whereToWatchLabel)")
                    .scaledFont(size: 17, weight: .semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Capsule().fill(watchCTAColor)
            )
            .shadow(color: watchCTAColor.opacity(0.55), radius: 22, y: 0)
        }
        .buttonStyle(.plain)
        .disabled(tmdbId == nil)
    }

    private var viewFullDetailsButton: some View {
        Button(action: close) {
            HStack(spacing: 6) {
                Text("View Full Details")
                    .scaledFont(size: 15, weight: .semibold)
                Image(systemName: "arrow.right")
                    .scaledFont(size: 13, weight: .semibold)
            }
            .foregroundStyle(Color.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.navy.ignoresSafeArea()
        PlayOnBottomSheet(
            isOpen: true,
            onClose: {},
            showTitle: "Succession",
            showSubtitle: "S4 E7 · Tailgate Party",
            thumbnailUrl: nil,
            onDeviceSelected: { _ in }
        )
    }
}
