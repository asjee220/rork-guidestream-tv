//
//  DeepDivesView.swift
//  GuideStreamTV
//
//  "Deep Dives" section displayed on the show detail screen between the
//  About synopsis and the episodes list. Shows up to 4 YouTube creator
//  channel cards plus an optional "+N more" card. Each card lets the user
//  open the creator's YouTube channel or follow/unfollow the creator.
//

import SwiftUI

// MARK: - Deep Dives section

struct DeepDivesView: View {
    let creators: [CreatorChannel]

    var body: some View {
        if creators.isEmpty { return AnyView(EmptyView()) }
        return AnyView(content)
    }

    @ViewBuilder
    private var content: some View {
        let visible = Array(creators.prefix(4))
        let overflow = creators.count - visible.count

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Deep Dives")
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(.white)

                Button {
                    openYouTube()
                } label: {
                    Image("youtube_attribution_icon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 28)
                }
                .accessibilityLabel("Open YouTube")
            }
            .padding(.horizontal, 20)

            Text("Video essays & theories about this show")
                .scaledFont(size: 12)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(visible) { creator in
                        CreatorChannelCard(creator: creator)
                    }

                    if overflow > 0 {
                        OverflowCard(count: overflow, allCreators: creators)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 18)
    }

    // MARK: - YouTube attribution

    private func openYouTube() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let appURL = URL(string: "youtube://") {
            UIApplication.shared.open(appURL, options: [:]) { ok in
                if !ok {
                    if let webURL = URL(string: "https://www.youtube.com") {
                        UIApplication.shared.open(webURL, options: [:])
                    }
                }
            }
        } else if let webURL = URL(string: "https://www.youtube.com") {
            UIApplication.shared.open(webURL, options: [:])
        }
    }
}

// MARK: - Single creator card

struct CreatorChannelCard: View {
    let creator: CreatorChannel

    var body: some View {
        VStack(spacing: 8) {
            // Avatar
            Group {
                if let avatarUrl = creator.avatarUrl, let url = URL(string: avatarUrl) {
                    RemoteImage(url: url, contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Text(creator.name.prefix(1).uppercased())
                                .scaledFont(size: 18, weight: .semibold)
                                .foregroundStyle(.white)
                        }
                }
            }
            .padding(.top, 4)

            // Channel name
            Text(creator.name)
                .scaledFont(size: 11, weight: .medium)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Subscriber label (only when non-nil)
            if let label = creator.subscriberLabel {
                Text(label)
                    .scaledFont(size: 9)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            // View button (full width)
            Button {
                openChannel()
            } label: {
                HStack(spacing: 4) {
                    Image("youtube_play_icon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 16)
                    Text("View")
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: 150)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            openChannel()
        }
    }

    private func openChannel() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Try the YouTube app scheme first, fall back to Safari.
        let channelId = creator.channelId
        if let appURL = URL(string: "youtube://www.youtube.com/channel/\(channelId)") {
            UIApplication.shared.open(appURL, options: [:]) { ok in
                if !ok {
                    // YouTube app not installed — open in Safari.
                    if let webURL = URL(string: creator.channelUrl) {
                        UIApplication.shared.open(webURL, options: [:])
                    }
                }
            }
        } else if let webURL = URL(string: creator.channelUrl) {
            UIApplication.shared.open(webURL, options: [:])
        }
    }
}

// MARK: - "+N more" overflow card

private struct OverflowCard: View {
    let count: Int
    let allCreators: [CreatorChannel]

    @State private var showSheet: Bool = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            VStack(spacing: 8) {
                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 48, height: 48)

                    Image(systemName: "plus")
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                Text("+\(count) more")
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundStyle(Color.textSecondary)

                Spacer(minLength: 0)

                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 28)
            }
            .padding(10)
            .frame(width: 150)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            AllCreatorsSheet(creators: allCreators)
        }
    }
}

// MARK: - Full creator list sheet

private struct AllCreatorsSheet: View {
    let creators: [CreatorChannel]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(creators) { creator in
                        AllCreatorsRow(creator: creator)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(BrandBackground())
            .navigationTitle("Deep Dives")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct AllCreatorsRow: View {
    let creator: CreatorChannel

    @State private var streams = StreamsViewModel.shared

    private var isFollowed: Bool {
        streams.userStreams.contains { $0.titleId == creator.titleId }
    }

    var body: some View {
        HStack(spacing: 12) {
            avatarView
            nameLabel
            Spacer(minLength: 0)
            followButton
            viewChannelButton
        }
        .padding(12)
        .background(rowBackground)
        .overlay(rowBorder)
    }

    // MARK: - Subviews

    private var avatarView: some View {
        Group {
            if let avatarUrl = creator.avatarUrl, let url = URL(string: avatarUrl) {
                RemoteImage(url: url, contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(creator.name.prefix(1).uppercased())
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundStyle(.white)
                    }
            }
        }
    }

    private var nameLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(creator.name)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(.white)
                .lineLimit(1)

            if let label = creator.subscriberLabel {
                Text("\(label) subscribers")
                    .scaledFont(size: 11)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var followIconName: String {
        isFollowed ? "checkmark" : "plus"
    }

    private var followIconColor: Color {
        isFollowed ? Color.orange : Color.white.opacity(0.7)
    }

    private var followCircleFill: some View {
        Circle()
            .fill(isFollowed ? Color.orange.opacity(0.15) : Color.white.opacity(0.06))
    }

    private var followCircleStroke: some View {
        Circle()
            .stroke(isFollowed ? Color.orange.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
    }

    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
            Image(systemName: followIconName)
                .scaledFont(size: 12, weight: .bold)
                .foregroundStyle(followIconColor)
                .frame(width: 32, height: 32)
                .background(followCircleFill)
                .overlay(followCircleStroke)
        }
        .buttonStyle(.plain)
    }

    private var viewChannelButton: some View {
        Button {
            openChannel()
        } label: {
            Text("View")
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(viewButtonBackground)
                .overlay(viewButtonBorder)
        }
        .buttonStyle(.plain)
    }

    private var viewButtonBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.clear)
    }

    private var viewButtonBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.04))
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 1)
    }

    private func toggleFollow() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            if isFollowed {
                await streams.removeFromMyStreams(titleId: creator.titleId)
            } else {
                await streams.addToMyStreams(
                    titleId: creator.titleId,
                    title: creator.name,
                    posterUrl: creator.avatarUrl,
                    platform: "youtube"
                )
            }
        }
    }

    private func openChannel() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let channelId = creator.channelId
        if let appURL = URL(string: "youtube://www.youtube.com/channel/\(channelId)") {
            UIApplication.shared.open(appURL, options: [:]) { ok in
                if !ok {
                    if let webURL = URL(string: creator.channelUrl) {
                        UIApplication.shared.open(webURL, options: [:])
                    }
                }
            }
        } else if let webURL = URL(string: creator.channelUrl) {
            UIApplication.shared.open(webURL, options: [:])
        }
    }
}
