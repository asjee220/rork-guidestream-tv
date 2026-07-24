//
//  EpisodeAvailabilitySection.swift
//  GuideStreamTV
//

import SwiftUI

// MARK: - Availability models

enum EpisodeAvailState {
 case available(serviceName: String, serviceColor: Color, deeplink: URL?)
 case locked(serviceName: String, serviceColor: Color)
 case unavailable
}

struct EpisodeAvailRow: Identifiable {
 let id = UUID()
 let seasonNumber: Int
 let episodeNumber: Int
 let title: String
 let runtime: Int?
 let state: EpisodeAvailState
}

struct SeasonCoverage: Identifiable {
 let id: Int
 let seasonNumber: Int
 let serviceName: String
 let serviceShort: String
 let serviceColor: Color
 let userHasSubscription: Bool
 let episodesCovered: Int
 let totalEpisodes: Int
}

// MARK: - Helpers

/// Shared brand color resolver used by both EpisodeAvailabilitySection and SearchView.
func gsBrandColor(for name: String) -> Color {
 let k = name.lowercased()
 if k.contains("netflix") { return Color(red:0.898,green:0.035,blue:0.078) }
 if k.contains("max") || k.contains("hbo") { return Color(red:0.357,green:0.176,blue:0.557) }
 if k.contains("hulu") { return Color(red:0.110,green:0.906,blue:0.514) }
 if k.contains("disney") { return Color(red:0.049,green:0.098,blue:0.420) }
 if k.contains("apple") { return Color(white:0.12) }
 if k.contains("prime") || k.contains("amazon") { return Color(red:0.0,green:0.659,blue:0.929) }
 if k.contains("paramount") { return Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255) }
 if k.contains("peacock") { return Color(red:0.043,green:0.043,blue:0.098) }
 if k.contains("youtube") { return Color(red:0.898,green:0.098,blue:0.098) }
 if k.contains("starz") { return Color(red:0.1,green:0.1,blue:0.1) }
 return Color(white:0.18)
}

/// Returns true when a Watchmode source name matches a user-facing platform string,
/// using the same fuzzy logic already in StreamingDeepLinker.
func gsSourceMatches(sourceName: String, platform: String) -> Bool {
 let s = sourceName.lowercased(), p = platform.lowercased()
 if p.contains("netflix") { return s.contains("netflix") }
 if p.contains("hbo") || p.contains("max") { return s.contains("max") || s.contains("hbo") }
 if p.contains("hulu") { return s.contains("hulu") }
 if p.contains("disney") { return s.contains("disney") }
 if p.contains("apple") { return s.contains("apple tv") }
 if p.contains("prime") || p.contains("amazon") { return s.contains("amazon") || s.contains("prime") }
 if p.contains("paramount") { return s.contains("paramount") }
 if p.contains("peacock") { return s.contains("peacock") }
 if p.contains("youtube") { return s.contains("youtube") }
 if p.contains("starz") { return s.contains("starz") }
 return s.contains(p) || p.contains(s)
}

func gsShortName(for name: String) -> String {
 let k = name.lowercased()
 if k.contains("netflix") { return "N" }
 if k.contains("max") { return "MAX" }
 if k.contains("hbo") { return "HBO" }
 if k.contains("hulu") { return "HULU" }
 if k.contains("disney") { return "D+" }
 if k.contains("apple") { return "TV+" }
 if k.contains("prime") || k.contains("amazon") { return "PRIME" }
 if k.contains("paramount") { return "P+" }
 if k.contains("peacock") { return "PCK" }
 if k.contains("youtube") { return "YT" }
 if k.contains("starz") { return "STARZ" }
 return String(name.prefix(4)).uppercased()
}

/// Normalises Watchmode source names to their canonical display forms.
/// Watchmode returns raw names like "Paramount Plus" or "Amazon Prime Video"
/// that diverge from the user-facing brand; this maps them to the expected
/// labels used everywhere else in the app.
func gsDisplayName(for raw: String) -> String {
 let k = raw.lowercased()
 if k.contains("paramount") {
  if k.contains("plus") || k.contains("+") { return "Paramount+" }
  return "Paramount+"
 }
 if k.contains("disney") {
  if k.contains("plus") || k.contains("+") { return "Disney+" }
  return "Disney+"
 }
 if k.contains("apple") && (k.contains("tv") || k.contains("+")) { return "Apple TV+" }
 if k.contains("max") || (k.contains("hbo") && k.contains("max")) { return "Max" }
 if k.contains("prime") || (k.contains("amazon") && k.contains("prime")) { return "Prime Video" }
 if k.contains("peacock") { return "Peacock" }
 if k.contains("crunchyroll") { return "Crunchyroll" }
 if k.contains("showtime") { return "Showtime" }
 return raw
}

/// Canonical brand key derived from a Watchmode source display name.
/// Lowercases, truncates at the first "(via ", strips known reseller
/// suffixes, then maps the remainder to a canonical catalogue id. The
/// appletv test intentionally precedes max and prime so that an Apple
/// title sold through Amazon keys as "appletv" and never as "prime".
func gsBrandKey(for name: String) -> String {
    var s = name.lowercased()
    if let viaRange = s.range(of: "(via ") {
        s = String(s[..<viaRange.lowerBound])
    }
    for suffix in ["amazon channel", "apple tv channel", "appletv channel",
                   "prime video channel", "roku premium subscription",
                   "roku premium", "youtube primetime channel"] {
        if s.contains(suffix) { s = s.replacingOccurrences(of: suffix, with: "") }
    }
    s = s.trimmingCharacters(in: .whitespaces)
    if s.isEmpty { s = name.lowercased().trimmingCharacters(in: .whitespaces) }
    s = String(s.unicodeScalars.filter { sc in
        (sc.value >= 0x61 && sc.value <= 0x7A) || (sc.value >= 0x30 && sc.value <= 0x39)
    })
    if s.contains("netflix") { return "netflix" }
    if s.contains("appletv") { return "appletv" }
    if s.contains("hbo") || s.contains("max") { return "max" }
    if s.contains("hulu") { return "hulu" }
    if s.contains("disney") { return "disney" }
    if s.contains("paramount") { return "paramount" }
    if s.contains("peacock") { return "peacock" }
    if s.contains("primevideo") || s.contains("amazonprime") || s.contains("amazonvideo") { return "prime" }
    if s.contains("crunchyroll") { return "crunchyroll" }
    if s.contains("showtime") { return "showtime" }
    if s.contains("starz") { return "starz" }
    if s.contains("youtube") { return "youtube" }
    return s
}

/// Canonical brand key derived from a deep-link URL's host. Matches on
/// host suffix so subdomains resolve correctly. Returns an empty string
/// for unrecognised or nil hosts so callers can allow the open.
func gsBrandKey(forURL url: URL) -> String {
    guard let host = url.host?.lowercased() else { return "" }
    if host.hasSuffix("netflix.com") { return "netflix" }
    if host.hasSuffix("tv.apple.com") || host.hasSuffix("apple.com") { return "appletv" }
    if host.hasSuffix("max.com") || host.hasSuffix("hbomax.com") || host.hasSuffix("play.max.com") { return "max" }
    if host.hasSuffix("hulu.com") { return "hulu" }
    if host.hasSuffix("disneyplus.com") { return "disney" }
    if host.hasSuffix("paramountplus.com") { return "paramount" }
    if host.hasSuffix("peacocktv.com") { return "peacock" }
    if host.hasSuffix("amazon.com") || host.hasSuffix("watch.amazon.com") || host.hasSuffix("primevideo.com") { return "prime" }
    if host.hasSuffix("crunchyroll.com") { return "crunchyroll" }
    if host.hasSuffix("showtime.com") || host.hasSuffix("sho.com") { return "showtime" }
    if host.hasSuffix("starz.com") { return "starz" }
    if host.hasSuffix("youtube.com") { return "youtube" }
    return ""
}

func gsSourceRank(_ s: WatchmodeSource) -> Int {
 switch s.type.lowercased() {
 case "sub": return 0; case "free": return 1
 case "tve": return 2; case "rent": return 3
 case "purchase","buy": return 4; default: return 5
 }
}

/// Builds EpisodeAvailRow array from TMDB episode list + Watchmode show-level sources.
func buildEpisodeAvailRows(
 tmdbEpisodes: [TMDBEpisode],
 seasonNumber: Int,
 sources: [WatchmodeSource],
 userServiceNames: [String]
) -> [EpisodeAvailRow] {
 let ranked = sources.sorted { gsSourceRank($0) < gsSourceRank($1) }
 // Show most recent episodes first (reverse episode-number order)
 let sorted = tmdbEpisodes.sorted { $0.episodeNumber > $1.episodeNumber }
 return sorted.map { ep in
 let best = ranked.first
 guard let src = best else {
 return EpisodeAvailRow(
 seasonNumber: seasonNumber,
 episodeNumber: ep.episodeNumber,
 title: ep.name ?? "Episode \(ep.episodeNumber)",
 runtime: ep.runtime,
 state: .unavailable
 )
 }
 let displayName = gsDisplayName(for: src.name)
 let color = gsBrandColor(for: src.name)
 let userHas = userServiceNames.contains(where: { gsSourceMatches(sourceName: src.name, platform: $0) })
 let deeplink: URL? = {
 // Build episode-specific URL from the show-level Watchmode URL by
 // appending season/episode path segments where the platform supports it.
 let baseURL: URL? = {
 if let ios = src.iosUrl, ios.hasPrefix("http"), let u = URL(string: ios) { return u }
 if let web = src.webUrl, web.hasPrefix("http"), let u = URL(string: web) { return u }
 return nil
 }()
 guard let base = baseURL else { return nil }
 return episodeDeeplinkURL(from: base, season: seasonNumber, episode: ep.episodeNumber)
 }()
 let state: EpisodeAvailState = userHas
 ? .available(serviceName: displayName, serviceColor: color, deeplink: deeplink)
 : .locked(serviceName: displayName, serviceColor: color)
 return EpisodeAvailRow(
 seasonNumber: seasonNumber,
 episodeNumber: ep.episodeNumber,
 title: ep.name ?? "Episode \(ep.episodeNumber)",
 runtime: ep.runtime,
 state: state
 )
 }
}

/// Builds an episode-specific deeplink URL by appending season/episode path
/// segments to the show-level web_url. Falls back to the original URL when
/// the platform doesn't use a path-based show structure.
func episodeDeeplinkURL(from base: URL, season: Int, episode: Int) -> URL {
 let baseStr = base.absoluteString
 let episodePath = "/season/\(season)/episode/\(episode)"
 // Services that support path-based season/episode deep links.
 // Paramount+, Peacock, and Hulu URLs follow the /shows/<name>/ pattern
 // and accept /season/X/episode/Y appended directly.
 if baseStr.contains("paramountplus.com") || baseStr.contains("paramount") {
 let stripped = baseStr.hasSuffix("/") ? String(baseStr.dropLast()) : baseStr
 return URL(string: stripped + episodePath) ?? base
 }
 if baseStr.contains("peacocktv.com") || baseStr.contains("peacock") {
 let stripped = baseStr.hasSuffix("/") ? String(baseStr.dropLast()) : baseStr
 return URL(string: stripped + episodePath) ?? base
 }
 if baseStr.contains("hulu.com") {
 let stripped = baseStr.hasSuffix("/") ? String(baseStr.dropLast()) : baseStr
 return URL(string: stripped + episodePath) ?? base
 }
 // Amazon uses query params instead of path segments.
 if baseStr.contains("amazon.com") || baseStr.contains("primevideo.com") || baseStr.contains("amazon") {
 return URL(string: baseStr + "?season=\(season)&episode=\(episode)") ?? base
 }
 // Netflix, Apple TV+, Max, Disney+ use opaque video/content IDs —
 // appending season/episode doesn't produce a valid deep link. Return
 // the show-level URL as a best-effort fallback to the show page.
 return base
}

/// Builds SeasonCoverage array from show-level Watchmode sources.
func buildSeasonCoverage(
 sources: [WatchmodeSource],
 totalEpisodes: Int,
 userServiceNames: [String]
) -> [SeasonCoverage] {
 var seen = Set<String>()
 var result: [SeasonCoverage] = []
 let ranked = sources.sorted { gsSourceRank($0) < gsSourceRank($1) }
 for src in ranked {
 let displayName = gsDisplayName(for: src.name)
 if seen.contains(displayName) { continue }
 seen.insert(displayName)
 let userHas = userServiceNames.contains(where: { gsSourceMatches(sourceName: src.name, platform: $0) })
 result.append(SeasonCoverage(
 id: result.count,
 seasonNumber: 1,
 serviceName: displayName,
 serviceShort: gsShortName(for: src.name),
 serviceColor: gsBrandColor(for: src.name),
 userHasSubscription: userHas,
 episodesCovered: totalEpisodes,
 totalEpisodes: max(totalEpisodes, 1)
 ))
 }
 return result
}

// MARK: - EpisodeAvailabilitySection view

struct EpisodeAvailabilitySection: View {
 let tmdbId: Int?
 let isTV: Bool
 let titleId: String
 let onEpisodeTap: (EpisodeAvailRow) -> Void

 @State private var seasons: [Int] = []
 @State private var selectedSeason: Int = 1
 @State private var episodeRows: [EpisodeAvailRow] = []
 @State private var coverages: [SeasonCoverage] = []
 @State private var isLoading = false
 @State private var showLevelSources: [WatchmodeSource] = []

 private var userServiceNames: [String] {
 StreamsViewModel.shared.userStreams.compactMap { $0.platform?.lowercased() }
 }

 var body: some View {
 VStack(alignment: .leading, spacing: 0) {

 // ── Coverage banner ──────────────────────────────────────
 if !coverages.isEmpty {
 VStack(alignment: .leading, spacing: 10) {
 Text("WHERE TO WATCH")
 .font(.system(size: 11, weight: .bold))
 .foregroundStyle(Color.white.opacity(0.4))
 .tracking(0.8)
 .padding(.horizontal, 16)
 .padding(.top, 16)

 VStack(spacing: 8) {
 ForEach(coverages) { cov in
 HStack(spacing: 10) {
 // Service pill
 Text(cov.serviceShort)
 .font(.system(size: 10, weight: .black))
 .foregroundStyle(.white)
 .padding(.horizontal, 8)
 .padding(.vertical, 4)
 .background(
 RoundedRectangle(cornerRadius: 6)
 .fill(cov.serviceColor.opacity(cov.userHasSubscription ? 1.0 : 0.3))
 )
 .opacity(cov.userHasSubscription ? 1 : 0.45)
 .frame(minWidth: 48)

 // Coverage bar
 GeometryReader { geo in
 ZStack(alignment: .leading) {
 RoundedRectangle(cornerRadius: 4)
 .fill(Color.white.opacity(0.08))
 RoundedRectangle(cornerRadius: 4)
 .fill(cov.serviceColor.opacity(cov.userHasSubscription ? 0.8 : 0.25))
 .frame(width: geo.size.width * CGFloat(cov.episodesCovered) / CGFloat(cov.totalEpisodes))
 }
 }
 .frame(height: 8)

 // Episode count
 Text("\(cov.episodesCovered) ep\(cov.episodesCovered == 1 ? "" : "s")")
 .font(.system(size: 11))
 .foregroundStyle(cov.userHasSubscription ? Color.white.opacity(0.7) : Color.white.opacity(0.3))
 .frame(minWidth: 36, alignment: .trailing)
 }
 .padding(.horizontal, 16)
 }
 }

 // Not subscribed note
 if coverages.contains(where: { !$0.userHasSubscription }) {
 let names = coverages.filter { !$0.userHasSubscription }.map { $0.serviceName }.joined(separator: ", ")
 HStack(spacing: 6) {
 Image(systemName: "lock.fill")
 .font(.system(size: 11))
 .foregroundStyle(Color.white.opacity(0.28))
 Text("Requires \(names) — not in your plan")
 .font(.system(size: 11))
 .foregroundStyle(Color.white.opacity(0.32))
 }
 .padding(.horizontal, 16)
 .padding(.top, 2)
 }

 // Unavailable note
 if episodeRows.contains(where: { if case .unavailable = $0.state { return true }; return false }) {
 HStack(spacing: 6) {
 Image(systemName: "info.circle")
 .font(.system(size: 11))
 .foregroundStyle(Color.white.opacity(0.28))
 Text("Some episodes not currently streaming anywhere")
 .font(.system(size: 11))
 .foregroundStyle(Color.white.opacity(0.32))
 }
 .padding(.horizontal, 16)
 .padding(.top, 2)
 }
 }
 .padding(.bottom, 12)
 .background(Color.white.opacity(0.04))
 .clipShape(RoundedRectangle(cornerRadius: 14))
 .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
 .padding(.horizontal, 16)
 .padding(.top, 8)
 }

 // ── Season selector ──────────────────────────────────────
 if seasons.count > 1 {
 ScrollView(.horizontal, showsIndicators: false) {
 HStack(spacing: 8) {
 ForEach(seasons, id: \.self) { s in
 Button("Season \(s)") { selectedSeason = s }
 .font(.system(size: 13, weight: .semibold))
 .foregroundStyle(selectedSeason == s ? .white : Color.white.opacity(0.5))
 .padding(.horizontal, 16)
 .padding(.vertical, 6)
 .background(
 Capsule().fill(selectedSeason == s ? Color.orange : Color.white.opacity(0.08))
 )
 .buttonStyle(.plain)
 }
 }
 .padding(.horizontal, 16)
 .padding(.vertical, 10)
 }
 }

 // ── Episode list header ──────────────────────────────────
 if isLoading {
 HStack { Spacer(); ProgressView().tint(Color.orange); Spacer() }
 .padding(.vertical, 24)
 } else if episodeRows.isEmpty {
 Text("No episode data available")
 .font(.system(size: 13))
 .foregroundStyle(Color.white.opacity(0.3))
 .frame(maxWidth: .infinity, alignment: .center)
 .padding(.vertical, 24)
 } else {
 episodeListBody
 }
 }
 .task { await loadInitialData() }
 .onChange(of: selectedSeason) { _, _ in
 Task { await loadEpisodesForSeason() }
 }
 }

 // ── Episode list sections ────────────────────────────────────────
 @ViewBuilder
 private var episodeListBody: some View {
 let available = episodeRows.filter { if case .available = $0.state { return true }; return false }
 let locked = episodeRows.filter { if case .locked = $0.state { return true }; return false }
 let unavailable = episodeRows.filter { if case .unavailable = $0.state { return true }; return false }

 VStack(alignment: .leading, spacing: 0) {

 if !available.isEmpty {
 sectionLabel("AVAILABLE TO WATCH")
 episodeRowsView(available)
 }

 if !locked.isEmpty {
 sectionLabel("REQUIRES SUBSCRIPTION")
 if let firstLocked = locked.first,
 case .locked(let svcName, _) = firstLocked.state {
 upgradeNudge(count: locked.count, serviceName: svcName)
 }
 episodeRowsView(locked)
 }

 if !unavailable.isEmpty {
 sectionLabel("NOT CURRENTLY STREAMING")
 episodeRowsView(unavailable)
 }
 }
 }

 private func sectionLabel(_ text: String) -> some View {
 Text(text)
 .font(.system(size: 11, weight: .bold))
 .foregroundStyle(Color.white.opacity(0.35))
 .tracking(0.8)
 .padding(.horizontal, 16)
 .padding(.top, 14)
 .padding(.bottom, 4)
 }

 private func episodeRowsView(_ rows: [EpisodeAvailRow]) -> some View {
 VStack(spacing: 0) {
 ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
 episodeRow(row)
 if idx < rows.count - 1 {
 Divider()
 .overlay(Color.white.opacity(0.05))
 .padding(.leading, 76)
 }
 }
 }
 }

 private func episodeRow(_ row: EpisodeAvailRow) -> some View {
 let isAvail: Bool = { if case .available = row.state { return true }; return false }()
 let isLocked: Bool = { if case .locked = row.state { return true }; return false }()

 var svcColor: Color = Color.white.opacity(0.15)
 var svcName: String = ""
 switch row.state {
 case .available(let n, let c, _): svcName = n; svcColor = c
 case .locked(let n, let c): svcName = n; svcColor = c
 case .unavailable: break
 }

 return HStack(spacing: 12) {
 // Episode number badge — S:1 EP:3 format
 ZStack {
 RoundedRectangle(cornerRadius: 8)
 .fill(isAvail ? svcColor.opacity(0.18) : isLocked ? svcColor.opacity(0.08) : Color.white.opacity(0.05))
 .frame(width: 52, height: 36)
 Text("S\(row.seasonNumber) EP\(row.episodeNumber)")
 .font(.system(size: 9, weight: .bold))
 .foregroundStyle(isAvail ? svcColor : Color.white.opacity(isLocked ? 0.22 : 0.18))
 .lineLimit(1)
 .minimumScaleFactor(0.8)
 }

 // Title + meta
 VStack(alignment: .leading, spacing: 2) {
 Text(row.title)
 .font(.system(size: 14, weight: .semibold))
 .foregroundStyle(isAvail ? .white : Color.white.opacity(0.3))
 .lineLimit(1)
 HStack(spacing: 4) {
 if let rt = row.runtime { Text("\(rt) min") }
 if isLocked && !svcName.isEmpty { Text("·"); Text(svcName) }
 if case .unavailable = row.state { Text("Not streaming") }
 }
 .font(.system(size: 11))
 .foregroundStyle(isAvail ? Color.white.opacity(0.4) : Color.white.opacity(0.2))
 }
 .frame(maxWidth: .infinity, alignment: .leading)

 // Right action indicator
 HStack(spacing: 6) {
 if isAvail {
 ZStack {
 RoundedRectangle(cornerRadius: 5)
 .fill(svcColor)
 .frame(width: 22, height: 22)
 Text(gsShortName(for: svcName))
 .font(.system(size: 7, weight: .black))
 .foregroundStyle(.white)
 }
 Image(systemName: "chevron.right")
 .font(.system(size: 13, weight: .semibold))
 .foregroundStyle(Color.orange)
 } else if isLocked {
 ZStack {
 RoundedRectangle(cornerRadius: 5)
 .fill(svcColor.opacity(0.25))
 .frame(width: 22, height: 22)
 Text(gsShortName(for: svcName))
 .font(.system(size: 7, weight: .black))
 .foregroundStyle(Color.white.opacity(0.3))
 }
 Image(systemName: "lock")
 .font(.system(size: 13))
 .foregroundStyle(Color.white.opacity(0.2))
 } else {
 Image(systemName: "clock")
 .font(.system(size: 14))
 .foregroundStyle(Color.white.opacity(0.18))
 }
 }
 }
 .padding(.horizontal, 16)
 .padding(.vertical, 10)
 .contentShape(Rectangle())
 .onTapGesture {
 if isAvail { onEpisodeTap(row) }
 }
 }

 private func upgradeNudge(count: Int, serviceName: String) -> some View {
 HStack(spacing: 10) {
 Image(systemName: "tv")
 .font(.system(size: 18))
 .foregroundStyle(Color.orange)
 VStack(alignment: .leading, spacing: 2) {
 Text("\(count) episode\(count == 1 ? "" : "s") on \(serviceName)")
 .font(.system(size: 13, weight: .semibold))
 .foregroundStyle(.white)
 Text("Not in your current plan")
 .font(.system(size: 11))
 .foregroundStyle(Color.white.opacity(0.45))
 }
 Spacer()
 Button("Add") {}
 .font(.system(size: 11, weight: .black))
 .foregroundStyle(.white)
 .padding(.horizontal, 10)
 .padding(.vertical, 5)
 .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange))
 .buttonStyle(.plain)
 }
 .padding(12)
 .background(Color.orange.opacity(0.08))
 .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25), lineWidth: 1))
 .clipShape(RoundedRectangle(cornerRadius: 12))
 .padding(.horizontal, 16)
 .padding(.vertical, 6)
 }

 // ── Data loading ─────────────────────────────────────────────────
 private func loadInitialData() async {
 guard let tmdbId, isTV else { return }
 isLoading = true
 defer { isLoading = false }
 async let tvDetail: TMDBTVDetail? = try? TMDBService.shared.getTVDetail(tmdbId: tmdbId)
 let tv = await tvDetail
 let n = max(1, tv?.numberOfSeasons ?? 1)
 seasons = Array(1...n)
 selectedSeason = n
 // Single edge-function call replaces the old Watchmode id + titleDetail
 // pair, routing through the server so no Watchmode API key ships in the
 // binary. The server applies the same US filter + dedupe + rank pipeline.
 if let response = await WatchmodeResolveService.resolve(tmdbId: tmdbId, isTV: true) {
 showLevelSources = response.usSources
 }
 await loadEpisodesForSeason()
 }

 private func loadEpisodesForSeason() async {
 guard let tmdbId else { return }
 isLoading = true
 defer { isLoading = false }
 guard let season = try? await TMDBService.shared.getSeason(tmdbId: tmdbId, seasonNumber: selectedSeason) else {
 episodeRows = []; coverages = []; return
 }
 let eps = season.episodes ?? []
 let names = userServiceNames
 episodeRows = buildEpisodeAvailRows(
 tmdbEpisodes: eps, seasonNumber: selectedSeason,
 sources: showLevelSources, userServiceNames: names
 )
 coverages = buildSeasonCoverage(
 sources: showLevelSources, totalEpisodes: eps.count, userServiceNames: names
 )
 }
}
