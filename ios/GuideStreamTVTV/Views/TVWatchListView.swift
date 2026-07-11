//
//  TVWatchListView.swift
//  GuideStreamTVTV
//
//  Focus grid of saved titles. Tapping any tile opens the same detail
//  sheet used on Home so the user can remove the title with one click.
//  Empty state nudges the user to head to Home and start saving.
//

import SwiftUI

struct TVWatchListView: View {
    @State private var streams = TVStreamsViewModel.shared
    @State private var social = SocialViewModel.shared
    @State private var pendingDetail: TVTitleDetail?

    private let columns: [GridItem] = Array(
        repeating: GridItem(.fixed(260), spacing: 36),
        count: 6
    )

    var body: some View {
        ZStack {
            TVTheme.backgroundGradient

            if streams.userStreams.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 32) {
                        header
                            .padding(.horizontal, 80)
                            .padding(.top, 24)

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 48) {
                            ForEach(sortedStreams) { row in
                                TVPosterCard(
                                    title: row.title ?? row.titleId,
                                    subtitle: row.platform,
                                    posterUrl: row.posterUrl,
                                    accent: TVTheme.orange,
                                    isSaved: true
                                ) {
                                    pendingDetail = TVTitleDetail(
                                        titleId: row.titleId,
                                        title: row.title ?? row.titleId,
                                        overview: nil,
                                        posterUrl: row.posterUrl,
                                        backdropUrl: row.posterUrl,
                                        tag: row.platform ?? "SAVED",
                                        accent: TVTheme.orange,
                                        year: nil,
                                        platform: row.platform
                                    )
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    if social.isWatched(row.titleId) {
                                        Circle()
                                            .fill(TVTheme.blue)
                                            .frame(width: 34, height: 34)
                                            .overlay {
                                                Image(systemName: "eye.fill")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                            .padding(10)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 80)
                        .padding(.bottom, 60)
                    }
                }
            }
        }
        .task {
            await streams.fetchUserStreams()
            await streams.fetchLatestContentDates()
            await social.loadAllWatched()
        }
        .sheet(item: $pendingDetail) { detail in
            TVTitleSheet(detail: detail) { _ in
                pendingDetail = nil
            }
        }
    }

    /// User streams sorted by recency (newest content first), then by
    /// date-added for titles without a `title_recency` row.
    private var sortedStreams: [TVUserStream] {
        let recencyMap = streams.latestContentAt
        return streams.userStreams.sorted { a, b in
            let aDate = recencyMap[a.titleId]
            let bDate = recencyMap[b.titleId]
            if let aD = aDate, let bD = bDate, aD != bD {
                return aD > bD
            }
            if aDate != nil && bDate == nil { return true }
            if aDate == nil && bDate != nil { return false }
            let aAdded = a.addedAt ?? Date.distantPast
            let bAdded = b.addedAt ?? Date.distantPast
            return aAdded > bAdded
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("Watch List")
                .font(.system(size: 48, weight: .black))
                .foregroundStyle(.white)
            Text("\(streams.userStreams.count)")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(TVTheme.orange, in: Capsule())
            Spacer()
            if streams.isLoading {
                ProgressView().tint(.white)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            Image(systemName: "popcorn.fill")
                .font(.system(size: 96, weight: .bold))
                .foregroundStyle(TVTheme.orange)
            Text("Your Watch List is empty")
                .font(.system(size: 38, weight: .black))
                .foregroundStyle(.white)
            Text("Open Home and click any title to add it. Saved shows appear here for everyone signed in to your account.")
                .font(.system(size: 22))
                .foregroundStyle(TVTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 700)
        }
        .padding(40)
    }
}
