//
//  TVTitleSheet.swift
//  GuideStreamTVTV
//
//  Detail sheet that opens when the user clicks a tile. Acts as the
//  single mutate-the-watch-list surface so cards across the app stay
//  decluttered — every tile just opens this sheet.
//

import SwiftUI

/// Lightweight payload describing a title that can be saved. Built from
/// either a TMDB result, news item, or watch list row.
struct TVTitleDetail: Identifiable, Hashable {
    let titleId: String
    let title: String
    let overview: String?
    let posterUrl: String?
    let backdropUrl: String?
    let tag: String
    let accent: Color
    let year: Int?
    let platform: String?

    var id: String { titleId }
}

// MARK: - Focus fields

private enum SheetFocus: Hashable {
    case play, like, watchList, close
}

// MARK: - Sheet

struct TVTitleSheet: View {
    let detail: TVTitleDetail
    let onDismiss: (Bool) -> Void

    @State private var streams = TVStreamsViewModel.shared
    @State private var social = SocialViewModel.shared
    @FocusState private var focusedField: SheetFocus?
    @Environment(\.dismiss) private var dismiss

    // Resolution state
    @State private var resolvedStreaming: TVWatchmodeResolver.TVResolvedStreaming?
    @State private var isResolving = false

    // Season / episode stepper (TV only)
    @State private var season: Int = 1
    @State private var episode: Int = 1

    // Parsed from titleId
    private var tmdbId: Int? {
        let parts = detail.titleId.split(separator: ":")
        guard parts.count >= 3, parts[0] == "tmdb" else { return nil }
        return Int(parts[2])
    }

    private var isTV: Bool {
        let parts = detail.titleId.split(separator: ":")
        guard parts.count >= 3, parts[0] == "tmdb" else { return false }
        return parts[1] == "tv"
    }

    private var isSaved: Bool {
        streams.contains(titleId: detail.titleId)
    }

    private var isLiked: Bool {
        social.isLiked(detail.titleId)
    }

    // Best display name for the Play button
    private var playServiceName: String {
        if let name = resolvedStreaming?.primarySource?.name, !name.isEmpty {
            return name
        }
        if let name = resolvedStreaming?.providerNameFallback, !name.isEmpty {
            return name
        }
        return detail.platform ?? "Streaming"
    }

    // Best deep-link URL for the Play button
    private var bestDeepLinkURL: URL? {
        let epTvos = resolvedStreaming?.episodeSource?.tvosUrl
        let primTvos = resolvedStreaming?.primarySource?.tvosUrl
        let epWeb = resolvedStreaming?.episodeSource?.webUrl
        let primWeb = resolvedStreaming?.primarySource?.webUrl
        let candidates = [epTvos, primTvos, epWeb, primWeb]
        for candidate in candidates {
            if let str = candidate, let url = URL(string: str) {
                return url
            }
        }
        return nil
    }

    // Best web URL for fallback
    private var bestWebURL: URL? {
        if let str = resolvedStreaming?.episodeSource?.webUrl ?? resolvedStreaming?.primarySource?.webUrl,
           let url = URL(string: str) {
            return url
        }
        return nil
    }

    // Synopsis text — resolved overview preferred, existing overview as fallback
    private var synopsisText: String? {
        if let resolved = resolvedStreaming?.overview, !resolved.isEmpty {
            return resolved
        }
        if let existing = detail.overview, !existing.isEmpty {
            return existing
        }
        return nil
    }

    var body: some View {
        ZStack {
            // Cinematic backdrop
            TVRemoteImage(urlString: detail.backdropUrl ?? detail.posterUrl, contentMode: .fill)
                .ignoresSafeArea()
                .overlay {
                    LinearGradient(
                        colors: [
                            .black.opacity(0.4),
                            .black.opacity(0.85),
                            .black
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            HStack(alignment: .top, spacing: 60) {
                // Poster
                TVRemoteImage(urlString: detail.posterUrl, contentMode: .fill)
                    .frame(width: 360, height: 540)
                    .clipShape(.rect(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.6), radius: 36, y: 18)

                VStack(alignment: .leading, spacing: 24) {
                    // Tag + year
                    HStack(spacing: 12) {
                        Text(detail.tag.uppercased())
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(detail.accent)
                            .tracking(2)
                        if let year = detail.year {
                            Text("·  \(String(year))")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(TVTheme.textSecondary)
                                .tracking(1)
                        }
                    }

                    // Title
                    Text(detail.title)
                        .font(.system(size: 56, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    // Synopsis
                    if let synopsis = synopsisText {
                        Text(synopsis)
                            .font(.system(size: 22))
                            .foregroundStyle(TVTheme.textSecondary)
                            .lineLimit(6)
                            .frame(maxWidth: 760, alignment: .leading)
                    }

                    // Season / Episode stepper (TV only)
                    if isTV {
                        seasonEpisodeStepper
                    }

                    // Platform badge (only when no resolved source)
                    if resolvedStreaming == nil,
                       let platform = detail.platform, !platform.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "play.tv.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(detail.accent)
                            Text("Streaming on \(platform)")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                    }

                    // Action buttons row
                    HStack(spacing: 24) {
                        // Play on <service>
                        playButton

                        // Like / Unlike
                        likeButton

                        // Watch List toggle
                        watchListButton

                        // Close
                        closeButton
                    }
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .task {
            await loadData()
        }
        .onChange(of: season) { _, _ in
            Task { await resolveStreamingData() }
        }
        .onChange(of: episode) { _, _ in
            Task { await resolveStreamingData() }
        }
    }

    // MARK: - Season / Episode stepper

    private var seasonEpisodeStepper: some View {
        HStack(spacing: 32) {
            // Season
            HStack(spacing: 16) {
                Button {
                    if season > 1 { season -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(season > 1 ? TVTheme.orange : TVTheme.textTertiary)
                }
                .buttonStyle(.card)
                .disabled(season <= 1)

                VStack(spacing: 2) {
                    Text("Season")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TVTheme.textTertiary)
                    Text("\(season)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(minWidth: 80)

                Button {
                    season += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(TVTheme.orange)
                }
                .buttonStyle(.card)
            }

            // Episode
            HStack(spacing: 16) {
                Button {
                    if episode > 1 { episode -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(episode > 1 ? TVTheme.orange : TVTheme.textTertiary)
                }
                .buttonStyle(.card)
                .disabled(episode <= 1)

                VStack(spacing: 2) {
                    Text("Episode")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TVTheme.textTertiary)
                    Text("\(episode)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(minWidth: 80)

                Button {
                    episode += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(TVTheme.orange)
                }
                .buttonStyle(.card)
            }
        }
    }

    // MARK: - Play button

    private var playButton: some View {
        Button {
            let name = playServiceName
            if let deepLink = bestDeepLinkURL {
                TVOSDeepLinker.open(
                    platform: name,
                    title: detail.title,
                    contentURL: bestWebURL,
                    tvosDeepLink: deepLink
                )
            } else {
                TVOSDeepLinker.open(
                    platform: name,
                    title: detail.title
                )
            }
        } label: {
            HStack(spacing: 14) {
                if isResolving && resolvedStreaming == nil {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 28, weight: .bold))
                }
                Text("Play on \(playServiceName.capitalized)")
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .buttonStyle(.card)
        .focused($focusedField, equals: .play)
        .disabled(isResolving && resolvedStreaming == nil)
    }

    // MARK: - Like button

    private var likeButton: some View {
        Button {
            Task {
                await social.toggleLike(
                    titleId: detail.titleId,
                    mediaType: isTV ? "tv" : "movie",
                    tmdbId: tmdbId
                )
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 24, weight: .bold))
                Text(isLiked ? "Liked" : "Like")
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(isLiked ? TVTheme.orange : .white)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .buttonStyle(.card)
        .focused($focusedField, equals: .like)
    }

    // MARK: - Watch List button

    private var watchListButton: some View {
        Button {
            Task {
                await streams.toggle(
                    titleId: detail.titleId,
                    title: detail.title,
                    posterUrl: detail.posterUrl,
                    platform: detail.platform
                )
                onDismiss(streams.contains(titleId: detail.titleId))
                dismiss()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                Text(isSaved ? "Remove from Watch List" : "Add to Watch List")
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .buttonStyle(.card)
        .focused($focusedField, equals: .watchList)
    }

    // MARK: - Close button

    private var closeButton: some View {
        Button {
            onDismiss(isSaved)
            dismiss()
        } label: {
            Text("Close")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
        }
        .buttonStyle(.card)
        .focused($focusedField, equals: .close)
    }

    // MARK: - Data loading

    private func loadData() async {
        // Refresh like state
        await social.refreshCounts(titleId: detail.titleId)

        // Resolve streaming sources
        await resolveStreamingData()

        // Set initial focus to Play
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            focusedField = .play
        }
    }

    private func resolveStreamingData() async {
        guard let tid = tmdbId else { return }
        isResolving = true
        let result = await TVWatchmodeResolver.shared.resolve(
            tmdbId: tid,
            isTV: isTV,
            season: isTV ? season : nil,
            episode: isTV ? episode : nil
        )
        resolvedStreaming = result
        isResolving = false
    }
}
