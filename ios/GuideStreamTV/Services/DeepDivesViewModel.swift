//
//  DeepDivesViewModel.swift
//  GuideStreamTV
//
//  Fetches YouTube creator channels that publish analysis, breakdown, and
//  theory content about a given show via the `youtube_show_creators` Supabase
//  edge function. Results are kept in memory for the lifetime of the view
//  model and never re-fetched for the same TMDB id + media type.
//

import Foundation
import Supabase

@MainActor
@Observable
final class DeepDivesViewModel {
    private(set) var creators: [CreatorChannel] = []
    private(set) var isLoading: Bool = false

    /// Deduplication key built from tmdbId + mediaType so we never re-fetch
    /// the same show twice during the lifetime of this instance.
    private var loadedKey: String?

    func load(tmdbId: Int, mediaType: String, showTitle: String) async {
        let key = "\(tmdbId)-\(mediaType)"
        guard loadedKey != key, !showTitle.isEmpty else { return }
        loadedKey = key

        isLoading = true
        defer { isLoading = false }

        do {
            let response: CreatorChannelResponse = try await SupabaseManager.shared.client.functions
                .invoke(
                    "youtube_show_creators",
                    options: FunctionInvokeOptions(body: [
                        "tmdb_id": String(tmdbId),
                        "media_type": mediaType,
                        "show_title": showTitle
                    ])
                )
            guard response.ok else { return }
            self.creators = response.creators ?? []
        } catch {
            print("[DeepDives] load failed: \(error.localizedDescription)")
            self.creators = []
        }
    }
}

// MARK: - Response envelope (private)

nonisolated fileprivate struct CreatorChannelResponse: Codable, Sendable {
    let ok: Bool
    let cached: Bool?
    let creators: [CreatorChannel]?
}
