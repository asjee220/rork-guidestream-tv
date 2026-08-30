//
//  CreatorsForYouListView.swift
//  GuideStreamTV
//
//  Full-screen browse behind the "Creators/Podcasts for You" rail's "See all"
//  link. The rail previously passed `onSeeAll: nil` to SectionGlassCard, so it
//  was the only recommendation rail on Home without one.
//
//  Seeded with the rail's own recommendations so the screen never blanks on
//  push, then replaced by a deeper fetch — the rail keeps the service default
//  of 12, this is the only caller that asks for more. Mirrors
//  `BingeWorthyListView`'s two-column grid and inline-ad cadence so the
//  "See all" destinations stay consistent.
//

import SwiftUI

struct CreatorsForYouListView: View {
    /// The rail's already-loaded recommendations, shown immediately.
    let initialCreators: [RecommendedCreator]
    /// Non-TMDB title_ids the user follows — the input the recommender scores
    /// against. Empty means there is nothing to deepen, so the seed stands.
    let followedIds: [String]
    var onSelect: (RecommendedCreator) -> Void

    /// How many recommendations the full list asks for.
    private static let deepLimit = 50

    @State private var creators: [RecommendedCreator]
    @State private var isLoadingDeeper: Bool = true

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    init(
        initialCreators: [RecommendedCreator],
        followedIds: [String],
        onSelect: @escaping (RecommendedCreator) -> Void
    ) {
        self.initialCreators = initialCreators
        self.followedIds = followedIds
        self.onSelect = onSelect
        _creators = State(initialValue: initialCreators)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(Array(creators.chunked(6).enumerated()), id: \.offset) { chunkIdx, chunk in
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(chunk) { creator in
                            Button(action: { onSelect(creator) }) {
                                CreatorGridCard(creator: creator)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if chunk.count >= 6 {
                        InlineAdSlotView(
                            slotIndex: chunkIdx,
                            adSource: "list_inline",
                            sectionKey: "list_inline_ad",
                            onDismiss: {}
                        )
                        .padding(.horizontal, 20)
                    }
                }

                if isLoadingDeeper {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(BrandBackground())
        .navigationTitle("Creators/Podcasts for You")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadDeeper() }
    }

    /// Re-runs the recommender with a larger limit. Deliberately only replaces
    /// the seed when the deeper fetch actually returns more, so a failure or a
    /// short result never shrinks what the user was already looking at.
    private func loadDeeper() async {
        defer { isLoadingDeeper = false }
        guard !followedIds.isEmpty else { return }
        guard let recs = try? await ContentSourcesService.shared.fetchRecommendedCreators(
            forFollowedIds: followedIds,
            limit: Self.deepLimit
        ), recs.count > creators.count else { return }
        creators = recs.map { r in
            RecommendedCreator(
                titleId: r.titleId,
                displayName: r.displayName,
                imageUrl: r.imageUrl,
                sourceType: r.sourceType,
                category: r.category,
                matchPercentage: r.matchPercentage
            )
        }
    }
}

/// Grid-sized twin of the rail's creator card — same poster, platform badge
/// and match chip, sized to the two-column grid instead of a fixed 164pt.
private struct CreatorGridCard: View {
    let creator: RecommendedCreator

    /// Poster proportions carried over from the rail card's 164x246 tile.
    private static let posterAspect: CGFloat = 164.0 / 246.0

    /// Brand tint for the platform badge and poster fallback, read from
    /// `SourceKind.brandColor` rather than re-declaring the palette.
    private var brandTint: Color { Color(hex: creator.kind.brandColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // `RemoteImage` is a `.resizable().aspectRatio(.fill)` image, so it
            // needs a definite width to size against — the rail gives it a fixed
            // 164pt. In a flexible grid column there is no such width, and the
            // image sized itself from its own intrinsic aspect and overflowed
            // the column. A `Color.clear` spacer with the rail's aspect ratio
            // takes the column's width, derives the height, and clips the image
            // into it.
            Color.clear
                .aspectRatio(Self.posterAspect, contentMode: .fit)
                .overlay {
                    RemoteImage(
                        urlString: creator.imageUrl,
                        contentMode: .fill,
                        fallbackColors: [brandTint.opacity(0.5), Color(red: 0.04, green: 0.02, blue: 0.10)]
                    )
                }
                .overlay(alignment: .bottomLeading) { platformBadge }
                .overlay(alignment: .topTrailing) { matchChip }
                .clipShape(.rect(cornerRadius: 10))

            Text(creator.displayName)
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var platformBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: creator.kind == .podcast ? "mic.fill" : "play.rectangle.fill")
                .font(.system(size: 7, weight: .bold))
            Text(creator.kind.displayLabel.uppercased())
                .scaledFont(size: 7, weight: .bold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(brandTint.opacity(0.8))
        )
        .padding(5)
        .allowsHitTesting(false)
    }

    private var matchChip: some View {
        Text("\(creator.matchPercentage)% Match")
            .scaledFont(size: 8, weight: .bold)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(red: 0.10, green: 0.44, blue: 0.91).opacity(0.88))
            )
            .padding(5)
            .allowsHitTesting(false)
    }
}
