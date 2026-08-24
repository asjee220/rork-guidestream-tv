//
//  TVSeeAllGridView.swift
//  GuideStreamTVTV
//
//  Shared full-screen "See all" destination. One reusable grid renders any
//  rail's poster items in five columns over the standard background
//  gradient. Selecting a card routes through the caller's pendingDetail
//  binding so TVTitleSheet presents over the grid.
//

import SwiftUI

/// One poster cell in a See-all grid, carrying everything needed to open
/// TVTitleSheet.
struct TVSeeAllGridItem: Identifiable {
    let titleId: String
    let title: String
    let subtitle: String?
    let posterUrl: String?
    let overview: String?
    let backdropUrl: String?
    let tag: String
    let year: Int?
    let isTVHint: Bool?

    var id: String { titleId }
}

/// Identifiable payload that drives TVHomeView's See-all full-screen cover:
/// the header title, the accent color, and the poster items the rail
/// already holds in state.
struct TVSeeAllGridPayload: Identifiable {
    let title: String
    let accent: Color
    let items: [TVSeeAllGridItem]

    var id: String { title }
}

struct TVSeeAllGridView: View {
    let payload: TVSeeAllGridPayload
    @Binding var pendingDetail: TVTitleDetail?

    @Environment(\.dismiss) private var dismiss
    @State private var streams = TVStreamsViewModel.shared
    @FocusState private var closeFocused: Bool

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 32),
        count: 5
    )

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                header

                LazyVGrid(columns: columns, spacing: 32) {
                    ForEach(payload.items) { item in
                        card(for: item)
                    }
                }

                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 80)
            .padding(.top, 56)
        }
        .background(TVTheme.backgroundGradient)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 20) {
            Capsule()
                .fill(payload.accent)
                .frame(width: 6, height: 40)
                .shadow(color: payload.accent.opacity(0.65), radius: 10)
            Text(payload.title)
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(.white)
            Spacer()
            closeButton
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(closeFocused ? Color.white : TVTheme.textSecondary)
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background(
                    Capsule().stroke(
                        closeFocused ? TVTheme.orange : Color.white.opacity(0.25),
                        lineWidth: closeFocused ? 2 : 1
                    )
                )
        }
        .buttonStyle(.plain)
        .focused($closeFocused)
    }

    // MARK: - Cards

    private func card(for item: TVSeeAllGridItem) -> some View {
        TVPosterCard(
            title: item.title,
            subtitle: item.subtitle,
            posterUrl: item.posterUrl,
            accent: payload.accent,
            isSaved: streams.contains(titleId: item.titleId)
        ) {
            pendingDetail = TVTitleDetail(
                titleId: item.titleId,
                title: item.title,
                overview: item.overview,
                posterUrl: item.posterUrl,
                backdropUrl: item.backdropUrl,
                tag: item.tag,
                accent: payload.accent,
                year: item.year,
                platform: nil,
                isTVHint: item.isTVHint
            )
        }
    }
}
