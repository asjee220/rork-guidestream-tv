//
//  CreatorDetailView.swift
//  GuideStreamTV
//
//  Lightweight destination for non-TMDB entities (YouTube, podcasts, Twitch, Kick).
//  Placeholder stub — displays metadata from content_sources and live_status.
//  No media playback is implemented here; that is a separate later prompt.
//

import SwiftUI

struct CreatorDetailView: View {
    let titleId: String
    let onBack: () -> Void

    @State private var source: ContentSource?
    @State private var liveStatus: LiveStatus?
    @State private var isLoading: Bool = true
    @State private var streams = StreamsViewModel.shared

    private var kind: SourceKind { SourceKind.from(titleId: titleId) }

    var body: some View {
        ZStack {
            BrandBackground()

            if isLoading {
                ProgressView().tint(Color.orange)
            } else if let source {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(sourceColor.opacity(0.15))
                                    .frame(width: 88, height: 88)
                                if let url = source.imageUrl {
                                    RemoteImage(urlString: url, contentMode: .fill, fallbackColors: [sourceColor, sourceColor.opacity(0.5)])
                                        .frame(width: 88, height: 88)
                                        .clipShape(Circle())
                                        .allowsHitTesting(false)
                                } else {
                                    Image(systemName: kindIcon)
                                        .scaledFont(size: 36, weight: .semibold)
                                        .foregroundStyle(sourceColor)
                                }
                            }

                            Text(source.displayName)
                                .scaledFont(size: 24, weight: .bold)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 8) {
                                SourceTypeBadge(kind: kind)
                                if let handle = source.handle {
                                    Text("@\(handle)")
                                        .scaledFont(size: 14)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }

                            if let liveStatus, liveStatus.isLive {
                                HStack(spacing: 8) {
                                    LivePill()
                                    Text("Live now")
                                        .scaledFont(size: 14, weight: .semibold)
                                        .foregroundStyle(Color.textSecondary)
                                    if let viewers = liveStatus.viewerCount {
                                        Text("·")
                                        Text(formatViewers(viewers))
                                            .scaledFont(size: 13)
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                }
                            }

                            // Follow button
                            Button {
                                toggleFollow()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isFollowed ? "checkmark" : "plus")
                                        .scaledFont(size: 14, weight: .bold)
                                    Text(isFollowed ? "Following" : "Follow")
                                        .scaledFont(size: 15, weight: .bold)
                                }
                                .foregroundStyle(isFollowed ? Color.textSecondary : .white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    Capsule()
                                        .fill(isFollowed ? Color.white.opacity(0.10) : Color.orange)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 40)
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 28)

                        Divider().overlay(Color.white.opacity(0.08)).padding(.horizontal, 20)

                        // Info
                        VStack(alignment: .leading, spacing: 20) {
                            if let desc = source.description {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ABOUT")
                                        .scaledFont(size: 12, weight: .heavy)
                                        .tracking(1.4)
                                        .foregroundStyle(Color.white.opacity(0.45))
                                    Text(desc)
                                        .scaledFont(size: 15)
                                        .foregroundStyle(Color.white.opacity(0.85))
                                        .lineSpacing(4)
                                }
                            }

                            if let liveStatus, liveStatus.isLive, let streamTitle = liveStatus.streamTitle {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("CURRENTLY STREAMING")
                                        .scaledFont(size: 12, weight: .heavy)
                                        .tracking(1.4)
                                        .foregroundStyle(Color.white.opacity(0.45))
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                        Text(streamTitle)
                                            .scaledFont(size: 16, weight: .semibold)
                                            .foregroundStyle(.white)
                                    }
                                    if let cat = liveStatus.category {
                                        Text(cat)
                                            .scaledFont(size: 13)
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                }
                            }

                            if let url = source.channelUrl ?? source.feedUrl {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("LINK")
                                        .scaledFont(size: 12, weight: .heavy)
                                        .tracking(1.4)
                                        .foregroundStyle(Color.white.opacity(0.45))
                                    Button {
                                        if let u = URL(string: url) {
                                            UIApplication.shared.open(u)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(url)
                                                .scaledFont(size: 13)
                                                .foregroundStyle(Color.orange)
                                                .lineLimit(1)
                                            Image(systemName: "arrow.up.right")
                                                .scaledFont(size: 11, weight: .semibold)
                                                .foregroundStyle(Color.orange)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if let cat = source.category {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("CATEGORY")
                                        .scaledFont(size: 12, weight: .heavy)
                                        .tracking(1.4)
                                        .foregroundStyle(Color.white.opacity(0.45))
                                    Text(cat)
                                        .scaledFont(size: 14)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 60)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .scaledFont(size: 36, weight: .regular)
                        .foregroundStyle(Color.textTertiary)
                    Text("Creator not found")
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private var isFollowed: Bool {
        streams.userStreams.contains { $0.titleId == titleId }
    }

    private var sourceColor: Color {
        switch kind {
        case .youtube: return Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255)
        case .podcast: return Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255)
        case .twitch: return Color(red: 0x91/255, green: 0x46/255, blue: 0xFF/255)
        case .kick: return Color(red: 0x53/255, green: 0xFC/255, blue: 0x18/255)
        case .tmdb: return Color.orange
        }
    }

    private var kindIcon: String {
        switch kind {
        case .youtube: return "play.rectangle.fill"
        case .podcast: return "mic.fill"
        case .twitch: return "gamecontroller.fill"
        case .kick: return "bolt.fill"
        case .tmdb: return "tv.fill"
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let sources = try await ContentSourcesService.shared.fetchSources()
            source = sources.first { $0.titleId == titleId }
            if let src = source, SourceKind.from(titleId: titleId).isLivestream {
                let statuses = try? await ContentSourcesService.shared.fetchLiveStatus(for: [titleId])
                liveStatus = statuses?.first
            }
        } catch {
            source = nil
        }
    }

    private func toggleFollow() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            if isFollowed {
                await streams.removeFromMyStreams(titleId: titleId)
            } else {
                await streams.addToMyStreams(
                    titleId: titleId,
                    title: source?.displayName ?? titleId,
                    posterUrl: source?.imageUrl,
                    platform: kind.sourceType
                )
            }
        }
    }

    private func formatViewers(_ count: Int) -> String {
        if count >= 1000 { return String(format: "%.1fK viewers", Double(count) / 1000) }
        return "\(count) viewers"
    }
}
