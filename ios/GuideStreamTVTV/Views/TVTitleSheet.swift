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

struct TVTitleSheet: View {
    let detail: TVTitleDetail
    let onDismiss: (Bool) -> Void

    @State private var streams = TVStreamsViewModel.shared
    @FocusState private var primaryFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isSaved: Bool {
        streams.contains(titleId: detail.titleId)
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
                    Text(detail.title)
                        .font(.system(size: 56, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    if let overview = detail.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 22))
                            .foregroundStyle(TVTheme.textSecondary)
                            .lineLimit(8)
                            .frame(maxWidth: 760, alignment: .leading)
                    }
                    if let platform = detail.platform, !platform.isEmpty {
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

                    HStack(spacing: 24) {
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
                        .focused($primaryFocused)

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
                    }
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                primaryFocused = true
            }
        }
    }
}
