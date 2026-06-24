//
//  WatchListBottomSheet.swift
//  GuideStreamTV
//
//  Two surfaces that share the same content view (`WatchListContent`):
//
//  * `WatchListBottomSheet` \u2014 modal sheet presented from the home feed's
//    "See all" link on the Watch List section.
//  * `WatchListView` \u2014 pushed onto the Profile stack so users can manage
//    their saved titles from the Profile tab as well.
//
//  Both surfaces pull the same `user_streams` Supabase rows, support
//  swipe-to-delete, and open the existing `EpisodeDetailSheet` so the user
//  can pick up where they left off.
//

import SwiftUI
import UIKit

// MARK: - Bottom sheet

struct WatchListBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WatchListContent()
                .navigationTitle("My Watch List")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Pushable destination (Profile tab)

struct WatchListView: View {
    var body: some View {
        WatchListContent()
            .navigationTitle("My Watch List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.navy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Shared content

/// Renders the watch list itself \u2014 list, empty state, or guest prompt \u2014 plus
/// background atmosphere and the detail-sheet plumbing. Wrap this view in
/// whatever navigation chrome the surface needs (sheet vs. push).
private struct WatchListContent: View {
    @State private var streams = StreamsViewModel.shared
    @State private var auth = AuthViewModel.shared
    @State private var detailSubject: DetailSubject?

    var body: some View {
        ZStack {
            BrandBackground()

            // Atmosphere \u2014 keeps the surface feeling like the rest of the app.
            GeometryReader { geo in
                Circle()
                    .fill(Color.blue.opacity(0.14))
                    .frame(width: geo.size.width * 0.9)
                    .blur(radius: 90)
                    .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.35)
                Circle()
                    .fill(Color.orange.opacity(0.10))
                    .frame(width: geo.size.width * 0.7)
                    .blur(radius: 80)
                    .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.4)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            content
        }
        .sheet(item: $detailSubject) { subject in
            EpisodeDetailSheet(subject: subject)
        }
        .task {
            await streams.fetchUserStreams()
        }
        .refreshable {
            await streams.fetchUserStreams()
        }
    }

    @ViewBuilder
    private var content: some View {
        if streams.userStreams.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                if !auth.isAuthenticated {
                    guestSyncBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                List {
                    ForEach(streams.userStreams) { item in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            detailSubject = .show(posterShow(from: item))
                        } label: {
                            WatchListRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.white.opacity(0.06))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                remove(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 88, height: 88)
                Image(systemName: "bookmark.fill")
                    .scaledFont(size: 32, weight: .semibold)
                    .foregroundStyle(Color.orange)
            }
            Text("Your watch list is empty")
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(.white)
            Text("Tap the + button on any show, movie, or game to save it here. We'll keep them ready for tonight.")
                .scaledFont(size: 13)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Small inline banner shown above a guest's watch list so they know the
    /// list lives on this device until they sign in. We deliberately do NOT
    /// gate the list behind a sign-in wall — guests can save and manage
    /// items locally; signing in later syncs everything up to Supabase.
    private var guestSyncBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "icloud.slash")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Color.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("Saved on this device")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(.white)
                Text("Sign in to sync your watch list across devices.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func remove(_ item: UserStream) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await streams.removeFromMyStreams(titleId: item.titleId) }
    }

    private func posterShow(from item: UserStream) -> PosterShow {
        // Show the platform name when we have one; otherwise show the
        // generic media type so we don't leak "Streaming" as if it were a
        // platform. The detail sheet's Watchmode lookup will fill in the
        // real service moments later.
        let platformMeta: String = {
            if let p = item.platform, !p.isEmpty, p.uppercased() != "STREAM" {
                return p.capitalized
            }
            return "Watch list"
        }()
        return PosterShow(
            title: item.title ?? "Watch List Item",
            meta: platformMeta,
            posterColors: HomeFallback.posterColors,
            symbol: "play.tv.fill",
            posterUrl: item.posterUrl,
            tmdbId: Int(item.titleId)
        )
    }
}

// MARK: - Row

private struct WatchListRow: View {
    let item: UserStream

    var body: some View {
        HStack(spacing: 12) {
            Color.black
                .frame(width: 60, height: 90)
                .overlay {
                    RemoteImage(
                        urlString: item.posterUrl,
                        contentMode: .fill,
                        fallbackColors: HomeFallback.posterColors
                    )
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                // Only render the platform chip when we have a real,
                // recognised streaming service. Generic placeholders like
                // "Streaming" or "Stream" used to leak through here and
                // confused users who saw the same neutral grey chip on
                // every saved title.
                if let platform = item.platform,
                   !platform.isEmpty,
                   platform.uppercased() != "STREAM",
                   platform.lowercased() != "streaming",
                   platform.lowercased() != "streaming services" {
                    Text(platform.uppercased())
                        .scaledFont(size: 9, weight: .heavy)
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(brandColor(for: platform))
                        )
                }
                Text(item.title ?? "Untitled")
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                if let added = item.addedAt {
                    Text("Added \(WatchListRow.formatter.localizedString(for: added, relativeTo: Date()))")
                        .scaledFont(size: 11)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

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
        if key.contains("crunchyroll") { return Color(red: 0xF4/255, green: 0x7B/255, blue: 0x20/255) }
        if key.contains("showtime") { return Color(red: 0xD8/255, green: 0x00/255, blue: 0x00/255) }
        if key.contains("starz") { return Color(white: 0.08) }
        if key.contains("youtube") { return Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255) }
        return Color(red: 0x6A/255, green: 0x3F/255, blue: 0xE0/255)
    }
}

#Preview {
    Color.navy.sheet(isPresented: .constant(true)) {
        WatchListBottomSheet()
    }
}
