//
//  ServicesBottomSheet.swift
//  GuideStreamTVTV
//
//  tvOS-adapted version of the services picker sheet. Mirrors the
//  onboarding "Which services do you have?" step so users can edit their
//  personalised feed from the Home page services pill. The tvOS layout
//  uses focusable tiles instead of the iOS bottom-sheet grid.
//

import SwiftUI

struct ServicesBottomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthViewModel.shared
    @State private var selected: Set<String>

    private let columns = [
        GridItem(.flexible(), spacing: 24),
        GridItem(.flexible(), spacing: 24),
        GridItem(.flexible(), spacing: 24),
        GridItem(.flexible(), spacing: 24)
    ]

    init() {
        _selected = State(initialValue: AuthViewModel.shared.selectedServices)
    }

    var body: some View {
        ZStack {
            Color.navy.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(StreamingCatalog.all) { service in
                            ServiceTile(
                                service: service,
                                isSelected: selected.contains(service.id),
                                onTap: { toggle(service.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 60)

                    HStack(spacing: 16) {
                        Button(action: dismissAndCancel) {
                            Text("Cancel")
                                .scaledFont(size: 22, weight: .semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 40)
                                .padding(.vertical, 18)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)

                        Button(action: saveAndDismiss) {
                            Text("Save")
                                .scaledFont(size: 22, weight: .bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 40)
                                .padding(.vertical, 18)
                                .background(Capsule().fill(Color.orange))
                                .shadow(color: Color.orange.opacity(0.5), radius: 14, y: 6)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .padding(.bottom, 60)
                }
                .padding(.top, 60)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Services")
                .scaledFont(size: 40, weight: .heavy)
                .foregroundStyle(.white)
            Text("Pick the streaming apps you have so your feed surfaces the right content.")
                .scaledFont(size: 18, weight: .regular)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 60)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func saveAndDismiss() {
        auth.setSelectedServices(selected)
        dismiss()
    }

    private func dismissAndCancel() {
        dismiss()
    }
}

// MARK: - WatchListBottomSheet

/// Lightweight watch-list browser surfaced from Home. Lists everything in
/// the user's `user_streams` rows. tvOS doesn't have a separate "manage"
/// flow so this sheet just renders the saved titles and lets the user pick
/// one to open in the detail sheet.
struct WatchListBottomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var streams = StreamsViewModel.shared
    @State private var detailSubject: DetailSubject?

    var body: some View {
        ZStack {
            Color.navy.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if streams.userStreams.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 24) {
                            ForEach(streams.userStreams) { row in
                                WatchListTile(row: row) {
                                    detailSubject = .show(rowAsPoster(row))
                                }
                            }
                        }
                        .padding(.horizontal, 60)
                    }

                    Button(action: { dismiss() }) {
                        Text("Done")
                            .scaledFont(size: 22, weight: .bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 18)
                            .background(Capsule().fill(Color.orange))
                            .shadow(color: Color.orange.opacity(0.5), radius: 14, y: 6)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .padding(.bottom, 60)
                }
                .padding(.top, 60)
            }
        }
        .fullScreenCover(item: $detailSubject) { subject in
            EpisodeDetailSheet(subject: subject)
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 24),
            GridItem(.flexible(), spacing: 24),
            GridItem(.flexible(), spacing: 24),
            GridItem(.flexible(), spacing: 24),
            GridItem(.flexible(), spacing: 24)
        ]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Watch List")
                .scaledFont(size: 40, weight: .heavy)
                .foregroundStyle(.white)
            Text("Everything you've saved to come back to later.")
                .scaledFont(size: 18, weight: .regular)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .scaledFont(size: 44, weight: .regular)
                .foregroundStyle(Color.textSecondary)
            Text("Nothing saved yet")
                .scaledFont(size: 22, weight: .semibold)
                .foregroundStyle(.white)
            Text("Add titles from the show or sports detail screens.")
                .scaledFont(size: 16, weight: .regular)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func rowAsPoster(_ row: UserStream) -> PosterShow {
        PosterShow(
            title: row.title ?? "Untitled",
            meta: row.platform ?? "Watch List",
            posterColors: HomeFallback.posterColors,
            symbol: "bookmark.fill",
            posterUrl: row.posterUrl,
            tmdbId: Int(row.titleId)
        )
    }
}

private struct WatchListTile: View {
    let row: UserStream
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                RemoteImage(
                    urlString: row.posterUrl,
                    contentMode: .fill,
                    fallbackColors: HomeFallback.posterColors
                )
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: 12))

                Text(row.title ?? "Untitled")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
