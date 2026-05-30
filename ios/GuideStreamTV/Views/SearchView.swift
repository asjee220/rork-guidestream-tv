//
//  SearchView.swift
//  GuideStreamTV
//

import SwiftUI

// MARK: - Search result model

struct SearchResult: Identifiable {
 let id: Int // TMDB id
 let title: String
 let isTV: Bool
 let posterUrl: String?
 let backdropUrl: String?
 let year: Int?
 let genreNames: [String]
 let serviceName: String?
 let serviceColor: Color
 let serviceShort: String
}

// MARK: - ViewModel

@Observable
final class SearchViewModel {
 var query: String = ""
 var isSearching: Bool = false
 var results: [SearchResult] = []
 var popular: [SearchResult] = []
 var error: String? = nil

 private var searchTask: Task<Void, Never>?

 func onQueryChange(_ q: String) {
 searchTask?.cancel()
 if q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
 results = []; isSearching = false; return
 }
 searchTask = Task {
 try? await Task.sleep(for: .milliseconds(250))
 guard !Task.isCancelled else { return }
 await search(q)
 }
 }

 func loadPopular() async {
 guard popular.isEmpty else { return }
 do {
 let tv = try await TMDBService.shared.getTrending(mediaType: "tv", timeWindow: "week")
 let movies = try await TMDBService.shared.getTrending(mediaType: "movie", timeWindow: "week")
 let combined = (tv + movies).prefix(18)
 let resolved = await withTaskGroup(of: SearchResult?.self) { group in
 for item in combined {
 group.addTask {
 let provider = try? await TMDBService.shared.getTopWatchProvider(tmdbId: item.id, isTV: item.isTV)
 let svcName = provider?.providerName
 let color = gsBrandColor(for: svcName ?? "")
 let short = gsShortName(for: svcName ?? "")
 guard svcName != nil else { return nil }
 return SearchResult(
 id: item.id, title: item.displayName, isTV: item.isTV,
 posterUrl: item.posterUrl, backdropUrl: item.backdropUrl,
 year: item.year, genreNames: [],
 serviceName: svcName, serviceColor: color, serviceShort: short
 )
 }
 }
 var out: [SearchResult] = []
 for await r in group { if let r { out.append(r) } }
 return out
 }
 await MainActor.run { self.popular = resolved }
 } catch {}
 }

 @MainActor
 private func search(_ q: String) async {
 isSearching = true
 defer { isSearching = false }
 do {
 let raw = try await TMDBService.shared.search(query: q)
 results = raw.compactMap { item in
 SearchResult(
 id: item.id, title: item.displayName, isTV: item.isTV,
 posterUrl: item.posterUrl, backdropUrl: item.backdropUrl,
 year: item.year, genreNames: [],
 serviceName: nil, serviceColor: Color(white:0.18), serviceShort: "")
 }
 } catch { self.error = error.localizedDescription }
 }
}

// MARK: - SearchView

struct SearchView: View {
 @Binding var isPresented: Bool
 var onSelectResult: ((SearchResult) -> Void)? = nil

 @State private var vm = SearchViewModel()
 @FocusState private var focused: Bool

 var body: some View {
 ZStack(alignment: .top) {
 Color.navy.ignoresSafeArea()

 VStack(spacing: 0) {
 // Search bar row
 HStack(spacing: 10) {
 HStack(spacing: 8) {
 Image(systemName: "magnifyingglass")
 .font(.system(size: 15, weight: .medium))
 .foregroundStyle(Color.orange)
 TextField("Search shows, movies, sports…", text: $vm.query)
 .focused($focused)
 .foregroundStyle(.white)
 .tint(Color.orange)
 .font(.system(size: 15))
 .autocorrectionDisabled()
 .onChange(of: vm.query) { _, q in vm.onQueryChange(q) }
 if !vm.query.isEmpty {
 Button {
 vm.query = ""
 vm.results = []
 } label: {
 Image(systemName: "xmark.circle.fill")
 .foregroundStyle(Color.white.opacity(0.4))
 }
 .buttonStyle(.plain)
 }
 }
 .padding(.horizontal, 12)
 .padding(.vertical, 10)
 .background(Color.white.opacity(0.07))
 .overlay(
 RoundedRectangle(cornerRadius: 14)
 .stroke(focused ? Color.orange.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
 )
 .clipShape(RoundedRectangle(cornerRadius: 14))

 Button("Cancel") {
 focused = false
 isPresented = false
 }
 .font(.system(size: 14, weight: .semibold))
 .foregroundStyle(Color.orange)
 }
 .padding(.horizontal, 16)
 .padding(.top, 56)
 .padding(.bottom, 10)

 Divider().overlay(Color.white.opacity(0.07))

 // Content area
 ScrollView(showsIndicators: false) {
 if vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
 popularGrid
 } else if vm.isSearching {
 HStack { Spacer(); ProgressView().tint(Color.orange); Spacer() }
 .padding(.top, 40)
 } else {
 typeAheadList
 }
 }
 }
 }
 .preferredColorScheme(.dark)
 .onAppear {
 focused = true
 Task { await vm.loadPopular() }
 }
 }

 // ── Popular poster grid ──────────────────────────────────────────
 private var popularGrid: some View {
 VStack(alignment: .leading, spacing: 0) {
 Text("POPULAR ON YOUR SERVICES")
 .font(.system(size: 11, weight: .bold))
 .foregroundStyle(Color.white.opacity(0.4))
 .tracking(0.8)
 .padding(.horizontal, 16)
 .padding(.top, 16)
 .padding(.bottom, 10)

 if vm.popular.isEmpty {
 HStack { Spacer(); ProgressView().tint(Color.orange); Spacer() }
 .padding(.top, 40)
 } else {
 LazyVGrid(columns: [
 GridItem(.flexible(), spacing: 8),
 GridItem(.flexible(), spacing: 8),
 GridItem(.flexible(), spacing: 8)
 ], spacing: 8) {
 ForEach(vm.popular) { result in
 PosterCell(result: result) { open(result) }
 }
 }
 .padding(.horizontal, 12)
 .padding(.bottom, 100)
 }
 }
 }

 // ── Type-ahead list ──────────────────────────────────────────────
 private var typeAheadList: some View {
 VStack(alignment: .leading, spacing: 0) {
 if vm.results.isEmpty {
 Text("No results for \"\(vm.query)\"")
 .font(.system(size: 13))
 .foregroundStyle(Color.white.opacity(0.35))
 .frame(maxWidth: .infinity, alignment: .center)
 .padding(.top, 40)
 } else {
 Text("\(vm.results.count) result\(vm.results.count == 1 ? "" : "s") for \"\(vm.query)\"")
 .font(.system(size: 11, weight: .bold))
 .foregroundStyle(Color.white.opacity(0.4))
 .tracking(0.8)
 .padding(.horizontal, 16)
 .padding(.top, 16)
 .padding(.bottom, 6)

 ForEach(Array(vm.results.enumerated()), id: \.element.id) { idx, result in
 TypeAheadRow(result: result, query: vm.query) { open(result) }
 if idx < vm.results.count - 1 {
 Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 58)
 }
 }
 Color.clear.frame(height: 100)
 }
 }
 }

 private func open(_ result: SearchResult) {
 if let cb = onSelectResult { cb(result); return }
 isPresented = false
 }
}

// MARK: - Sub-views

private struct PosterCell: View {
 let result: SearchResult
 let onTap: () -> Void

 var body: some View {
 Button(action: onTap) {
 ZStack(alignment: .bottom) {
 RoundedRectangle(cornerRadius: 10)
 .fill(Color.white.opacity(0.06))
 .aspectRatio(2/3, contentMode: .fit)
 .overlay {
 if let url = result.posterUrl.flatMap(URL.init) {
 AsyncImage(url: url) { phase in
 if case .success(let img) = phase {
 img.resizable().aspectRatio(contentMode: .fill)
 }
 }
 }
 }
 .clipShape(RoundedRectangle(cornerRadius: 10))

 LinearGradient(
 colors: [.clear, Color.black.opacity(0.9)],
 startPoint: .center, endPoint: .bottom
 )
 .clipShape(RoundedRectangle(cornerRadius: 10))

 VStack(alignment: .leading, spacing: 2) {
 Text(result.title)
 .font(.system(size: 9, weight: .bold))
 .foregroundStyle(.white)
 .lineLimit(2)
 .frame(maxWidth: .infinity, alignment: .leading)
 }
 .padding(6)
 .frame(maxWidth: .infinity, alignment: .leading)

 if result.serviceName != nil {
 Text(result.serviceShort)
 .font(.system(size: 8, weight: .black))
 .foregroundStyle(.white)
 .padding(.horizontal, 5)
 .padding(.vertical, 2)
 .background(RoundedRectangle(cornerRadius: 4).fill(result.serviceColor))
 .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
 .padding(5)
 }
 }
 }
 .buttonStyle(.plain)
 }
}

private struct TypeAheadRow: View {
 let result: SearchResult
 let query: String
 let onTap: () -> Void

 var body: some View {
 Button(action: onTap) {
 HStack(spacing: 10) {
 // Poster thumbnail — 80% scale of popular grid poster
 RoundedRectangle(cornerRadius: 6)
 .fill(Color.white.opacity(0.06))
 .frame(width: 35, height: 48)
 .overlay {
 if let url = result.posterUrl.flatMap(URL.init) {
 AsyncImage(url: url) { phase in
 if case .success(let img) = phase {
 img.resizable().aspectRatio(contentMode: .fill)
 }
 }
 .clipShape(RoundedRectangle(cornerRadius: 6))
 }
 }

 VStack(alignment: .leading, spacing: 2) {
 highlightedTitle
 Text(result.isTV ? "TV Series" : "Movie")
 .font(.system(size: 9))
 .foregroundStyle(Color.white.opacity(0.4))
 }
 .frame(maxWidth: .infinity, alignment: .leading)

 if let svc = result.serviceName {
 Text(result.serviceShort)
 .font(.system(size: 7, weight: .black))
 .foregroundStyle(.white)
 .padding(.horizontal, 5)
 .padding(.vertical, 2)
 .background(RoundedRectangle(cornerRadius: 4).fill(result.serviceColor))
 }

 Image(systemName: "chevron.right")
 .font(.system(size: 10, weight: .semibold))
 .foregroundStyle(Color.white.opacity(0.2))
 }
 .padding(.horizontal, 16)
 .padding(.vertical, 7)
 .contentShape(Rectangle())
 }
 .buttonStyle(.plain)
 }

 /// Uses a Group so both branches return the same opaque type without forced casts.
 @ViewBuilder
 private var highlightedTitle: some View {
 let lower = result.title.lowercased()
 let qLower = query.lowercased()
 if let range = lower.range(of: qLower) {
 let start = result.title[result.title.startIndex..<range.lowerBound]
 let match = result.title[range]
 let end = result.title[range.upperBound...]
 Group {
 Text(String(start)).foregroundStyle(.white) +
 Text(String(match)).foregroundStyle(Color.orange) +
 Text(String(end)).foregroundStyle(.white)
 }
 .font(.system(size: 11, weight: .semibold))
 } else {
 Text(result.title)
 .foregroundStyle(.white)
 .font(.system(size: 11, weight: .semibold))
 }
 }
}
