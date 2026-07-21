//
//  WatchmodeService.swift
//  GuideStreamTV
//
//  Wire-shape models for Watchmode source data. The WatchmodeService struct
//  and all six of its methods (titleDetail, fetchTopTitles, search,
//  upcomingStreamingReleases, episodeSources, watchmodeId) have been removed
//  — every Watchmode call now routes through the watchmode_resolve Supabase
//  edge function via WatchmodeResolveService so the hardcoded Watchmode API
//  key no longer ships in the binary. These Decodable model types remain
//  because downstream views (ShowDetailScreen, HomeDestinations, PlayOnBottomSheet,
//  EpisodeAvailabilitySection, StreamingDeepLinker, CastToTVSheet, ReelsScreen)
//  and StreamingSourceResolver still reference them as the shared source/detail
//  shapes. The edge function returns the same snake_case wire shape, so
//  WatchmodeSource is reused for decoding its responses.
//

import Foundation

nonisolated struct WatchmodeSource: Decodable, Hashable, Sendable, Identifiable {
    let sourceId: Int
    let name: String
    let type: String
    let region: String?
    let iosUrl: String?
    let androidUrl: String?
    let webUrl: String?
    let format: String?
    let endDate: String?
    let rokuUrl: String?
    let tvosUrl: String?
    let androidTvUrl: String?
    let price: Double?

    var id: String { "\(sourceId)-\(format ?? "")-\(region ?? "")" }

    enum CodingKeys: String, CodingKey {
        case sourceId = "source_id"
        case name, type, region, format
        case iosUrl = "ios_url"
        case androidUrl = "android_url"
        case webUrl = "web_url"
        case endDate = "end_date"
        case rokuUrl = "roku_url"
        case tvosUrl = "tvos_url"
        case androidTvUrl = "android_tv_url"
        case price = "price"
    }
}

nonisolated struct WatchmodeTitleDetail: Decodable, Sendable {
    let id: Int
    let title: String
    let year: Int?
    let userRating: Double?
    let plotOverview: String?
    let genreNames: [String]?
    let trailer: String?
    let posterUrl: String?
    let backdrop: String?
    let releaseDate: String?
    let endYear: Int?
    let runtimeMinutes: Int?
    let usRating: String?
    let type: String?
    let sources: [WatchmodeSource]?

    enum CodingKeys: String, CodingKey {
        case id, title, year, trailer, type, sources
        case userRating = "user_rating"
        case plotOverview = "plot_overview"
        case genreNames = "genre_names"
        case posterUrl = "poster"
        case backdrop
        case releaseDate = "release_date"
        case endYear = "end_year"
        case runtimeMinutes = "runtime_minutes"
        case usRating = "us_rating"
    }
}
