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
                            ForEach(streams.userStreams) { row in
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
                            }
                        }
                        .padding(.horizontal, 80)
                        .padding(.bottom, 60)
                    }
                }
            }
        }
        .task { await streams.fetchUserStreams() }
        .sheet(item: $pendingDetail) { detail in
            TVTitleSheet(detail: detail) { _ in
                pendingDetail = nil
            }
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
