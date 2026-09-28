//
//  MacTitleSheet.swift
//  GuideStreamTVMac
//
//  Title detail: art, overview, Where to Watch and the watchlist toggle.
//  Sources come from `watchmode_resolve` (TVWatchmodeResolver), the same
//  call and personalisation the phone and Apple TV make. On a Mac every
//  source opens its web player, since the streaming apps are web-first here.
//

import SwiftUI

struct MacTitleSheet: View {
    let ref: MacTitleRef
    @Environment(\.dismiss) private var dismiss
    @State private var streams = TVStreamsViewModel.shared
    @State private var resolved: TVWatchmodeResolver.TVResolvedStreaming?
    @State private var loading = true
    @State private var backdropUrl: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    TVRemoteImage(urlString: backdropUrl ?? ref.backdropUrl ?? ref.posterUrl, contentMode: .fill)
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    LinearGradient(colors: [.clear, MacColor.navy], startPoint: .center, endPoint: .bottom)
                    HStack(alignment: .bottom, spacing: 18) {
                        TVRemoteImage(urlString: ref.posterUrl, contentMode: .fill)
                            .frame(width: 120, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ref.title).font(.system(size: 28, weight: .bold)).lineLimit(2)
                            Text(metaLine).font(.system(size: 13, weight: .medium)).foregroundStyle(MacColor.text2)
                        }
                    }
                    .padding(24)
                }

                VStack(alignment: .leading, spacing: 20) {
                    if let overview = resolved?.overview ?? ref.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.8))
                            .lineSpacing(3)
                            .frame(maxWidth: 640, alignment: .leading)
                    }

                    HStack(spacing: 10) {
                        if let primary = resolved?.primarySource, primary.webUrl != nil {
                            Button { open(primary) } label: {
                                Label(ctaLabel(primary), systemImage: "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color(red: 0.03, green: 0.02, blue: 0.02))
                                    .padding(.horizontal, 18).padding(.vertical, 11)
                                    .background(MacColor.orange, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        Button { Task { await toggleWatchlist() } } label: {
                            Label(isSaved ? "In watchlist" : "Watchlist", systemImage: isSaved ? "checkmark" : "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 16).padding(.vertical, 11)
                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(!AuthViewModel.shared.isAuthenticated)
                        .help(AuthViewModel.shared.isAuthenticated ? "" : "Sign in to keep a watchlist")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("WHERE TO WATCH")
                            .font(.system(size: 11, weight: .bold)).tracking(1.2)
                            .foregroundStyle(MacColor.text3)
                        if loading {
                            ProgressView().controlSize(.small)
                        } else if sources.isEmpty {
                            Text("Not streaming in your region right now.")
                                .font(.system(size: 13)).foregroundStyle(MacColor.text2)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], alignment: .leading, spacing: 10) {
                                ForEach(sources, id: \.sourceId) { src in sourceRow(src) }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 620)
        .background(MacColor.navy)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(14)
        }
        .task { await load() }
    }

    private var isSaved: Bool { streams.contains(titleId: ref.titleId) }

    private var metaLine: String {
        var parts = [ref.isTV ? "Series" : "Movie"]
        if let y = ref.year { parts.append(String(y)) }
        return parts.joined(separator: " · ")
    }

    /// Subscription sources first, then the rest; one row per service.
    private var sources: [TVWatchmodeResolver.TVResolvedSource] {
        var seen = Set<String>()
        return (resolved?.usSources ?? [])
            .filter { $0.webUrl != nil && seen.insert($0.name).inserted }
            .sorted { ($0.type == "sub" ? 0 : 1) < ($1.type == "sub" ? 0 : 1) }
    }

    private func sourceRow(_ src: TVWatchmodeResolver.TVResolvedSource) -> some View {
        let platform = Platform.from(providerName: src.name)
        return Button { open(src) } label: {
            HStack(spacing: 10) {
                Circle().fill(platform?.color ?? Color.white.opacity(0.3)).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(platform?.displayName ?? src.name).font(.system(size: 13, weight: .semibold))
                    Text(kindLabel(src)).font(.system(size: 11)).foregroundStyle(MacColor.text3)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(MacColor.text2)
            }
            .padding(12)
            .background(MacColor.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MacColor.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func kindLabel(_ src: TVWatchmodeResolver.TVResolvedSource) -> String {
        switch src.type {
        case "sub": return AuthViewModel.shared.subscribesToService(named: src.name) ? "Included with your plan" : "Subscription"
        case "free": return "Free"
        case "rent": return src.price.map { String(format: "Rent · $%.2f", $0) } ?? "Rent"
        case "buy": return src.price.map { String(format: "Buy · $%.2f", $0) } ?? "Buy"
        default: return src.type.capitalized
        }
    }

    private func ctaLabel(_ src: TVWatchmodeResolver.TVResolvedSource) -> String {
        let name = Platform.from(providerName: src.name)?.displayName ?? src.name
        return AuthViewModel.shared.subscribesToService(named: src.name) || src.type == "free"
            ? "Watch on \(name)" : "Get on \(name)"
    }

    private func open(_ src: TVWatchmodeResolver.TVResolvedSource) {
        guard let raw = src.webUrl, let url = URL(string: raw) else { return }
        WatchIntentLogger.shared.log(eventType: .deeplinkFired, titleId: ref.titleId,
                                     platformId: src.name.lowercased(),
                                     metadata: ["surface": "mac_title_sheet", "source_type": src.type])
        MacLinkOpener.open(url)
    }

    private func toggleWatchlist() async {
        if isSaved {
            await streams.remove(titleId: ref.titleId)
        } else {
            await streams.add(titleId: ref.titleId, title: ref.title, posterUrl: ref.posterUrl,
                              platform: resolved?.primarySource?.name)
        }
    }

    private func load() async {
        WatchIntentLogger.shared.log(eventType: .cardTapped, titleId: ref.titleId, metadata: ["surface": "mac"])
        if ref.backdropUrl == nil, let id = ref.tmdbId,
           let path = await TVTMDBService.shared.getBackdropPath(tmdbId: id, isTV: ref.isTV) {
            backdropUrl = TVTMDBImage.url(path, size: .backdrop1280)
        }
        if let id = ref.tmdbId {
            resolved = await TVWatchmodeResolver.shared.resolve(
                tmdbId: id, isTV: ref.isTV, season: nil, episode: nil,
                subscribedServices: Array(AuthViewModel.shared.selectedServices)
            )
        }
        loading = false
    }
}
