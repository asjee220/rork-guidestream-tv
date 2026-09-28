//
//  MacReelsView.swift
//  GuideStreamTVMac
//
//  Reels on Mac: the phone's trailer feed (TVReelsViewModel) played in
//  YouTube's own embedded player. A desktop layout rather than a vertical
//  swipe: the trailer large, its details and actions beneath, Up Next on
//  the right. ↑/↓ or the buttons step through; a trailer that ends moves on.
//

import SwiftUI

struct MacReelsView: View {
    @State private var model = TVReelsViewModel.shared
    @State private var social = TVSocialService.shared
    @State private var streams = TVStreamsViewModel.shared
    @State private var index = 0
    @State private var keyIndex = 0
    @FocusState private var focused: Bool
    @Environment(\.openTitle) private var openTitle

    var body: some View {
        Group {
            if model.reels.isEmpty {
                if model.isLoading {
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MacEmptyState(icon: "play.rectangle", title: "No trailers right now", message: "Check back soon.")
                }
            } else {
                HStack(alignment: .top, spacing: 20) {
                    main
                    upNext.frame(width: 280)
                }
                .padding(MacLayout.contentPadding)
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { step(1); return .handled }
        .onKeyPress(.upArrow) { step(-1); return .handled }
        .task {
            await model.load()
            focused = true
        }
    }

    private var current: TVReelItem? { model.reels.indices.contains(index) ? model.reels[index] : nil }

    @ViewBuilder private var main: some View {
        if let reel = current {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    Color.black
                    if reel.trailerKeys.indices.contains(keyIndex) {
                        MacYouTubePlayer(
                            videoId: reel.trailerKeys[keyIndex],
                            onEnded: { step(1) },
                            onUnplayable: {
                                if keyIndex + 1 < reel.trailerKeys.count { keyIndex += 1 } else { step(1) }
                            }
                        )
                        // No .id: one WKWebView for the whole feed; stepping
                        // swaps the video with loadVideoById instead of
                        // reloading YouTube's IFrame API every reel.
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: MacLayout.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: MacLayout.cardRadius).stroke(MacColor.hairline, lineWidth: 1))

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(reel.title).font(.system(size: 24, weight: .bold)).lineLimit(2)
                        Text(meta(reel)).font(.system(size: 13, weight: .medium)).foregroundStyle(MacColor.text2)
                        if !reel.synopsis.isEmpty {
                            Text(reel.synopsis).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.75))
                                .lineLimit(3).frame(maxWidth: 640, alignment: .leading).padding(.top, 4)
                        }
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        actionButton(social.isLiked(reel.canonicalTitleId) ? "heart.fill" : "heart",
                                     label: likeLabel(reel), tint: social.isLiked(reel.canonicalTitleId) ? MacColor.live : nil) {
                            Task { await social.toggleLike(titleId: reel.canonicalTitleId, mediaType: reel.mediaType, tmdbId: reel.tmdbId) }
                        }
                        .disabled(!AuthViewModel.shared.isAuthenticated)
                        actionButton(isSaved(reel) ? "checkmark" : "plus", label: "Watchlist", tint: nil) {
                            Task { await toggleSaved(reel) }
                        }
                        .disabled(!AuthViewModel.shared.isAuthenticated)
                        actionButton("play.tv", label: "Where to watch", tint: MacColor.orange) {
                            openTitle(MacTitleRef(titleId: reel.canonicalTitleId, tmdbId: reel.tmdbId, isTV: reel.isTV,
                                                  title: reel.title, posterUrl: reel.posterUrl,
                                                  backdropUrl: reel.backdropUrl, overview: reel.synopsis, year: reel.year))
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button { step(-1) } label: { Label("Previous", systemImage: "chevron.up") }
                        .disabled(index == 0)
                    Button { step(1) } label: { Label("Next", systemImage: "chevron.down") }
                        .disabled(index >= model.reels.count - 1)
                    Text("\(index + 1) of \(model.reels.count)\(model.isLoadingMore ? " · loading more…" : "")")
                        .font(.system(size: 12)).foregroundStyle(MacColor.text3)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { logView(reel) }
            .onChange(of: index) { _, _ in if let r = current { logView(r) } }
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Up next").font(.system(size: 15, weight: .semibold))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(model.reels.enumerated()).dropFirst(index + 1).prefix(20), id: \.element.id) { i, reel in
                        Button { jump(to: i) } label: {
                            HStack(spacing: 10) {
                                TVRemoteImage(urlString: reel.backdropUrl ?? reel.posterUrl, contentMode: .fill)
                                    .frame(width: 112, height: 63)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(reel.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                    Text(reel.isTV ? "Series" : "Movie").font(.system(size: 11)).foregroundStyle(MacColor.text3)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(MacColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(MacColor.hairline, lineWidth: 1))
    }

    private func actionButton(_ icon: String, label: String, tint: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint == MacColor.orange ? Color(red: 0.03, green: 0.02, blue: 0.02) : (tint ?? .white))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(tint == MacColor.orange ? MacColor.orange : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func meta(_ r: TVReelItem) -> String {
        [r.isTV ? "Series" : "Movie", r.year.map(String.init), r.platformName].compactMap { $0 }.joined(separator: " · ")
    }

    private func likeLabel(_ r: TVReelItem) -> String {
        let n = social.likeCount(r.canonicalTitleId)
        return n > 0 ? "\(n)" : "Like"
    }

    private func isSaved(_ r: TVReelItem) -> Bool {
        streams.contains(titleId: String(r.tmdbId)) || streams.contains(titleId: r.canonicalTitleId)
    }

    private func toggleSaved(_ r: TVReelItem) async {
        if isSaved(r) {
            if streams.contains(titleId: String(r.tmdbId)) { await streams.remove(titleId: String(r.tmdbId)) }
            if streams.contains(titleId: r.canonicalTitleId) { await streams.remove(titleId: r.canonicalTitleId) }
        } else {
            await streams.add(titleId: String(r.tmdbId), title: r.title, posterUrl: r.posterUrl, platform: r.platformName, isTV: r.isTV)
        }
    }

    private func step(_ delta: Int) { jump(to: index + delta) }

    private func jump(to i: Int) {
        guard model.reels.indices.contains(i) else { return }
        index = i
        keyIndex = 0
        Task { await model.loadMoreIfNeeded(currentIndex: i) }
    }

    private func logView(_ r: TVReelItem) {
        WatchIntentLogger.shared.log(eventType: .trailerViewed, titleId: r.canonicalTitleId,
                                     metadata: ["surface": "mac_reels", "trailer_key": r.trailerKeys.first ?? ""])
    }
}
