//
//  BrowseFilterSheet.swift
//  GuideStreamTV
//
//  Grouped filter sheet for Search & Browse.
//
//  The primary button states the outcome — "Show 214 titles" — and recounts as
//  the draft changes, so the sheet answers "did that help?" before it is
//  dismissed. Nothing is applied until the button is pressed.
//

import SwiftUI

// MARK: - Year presets

/// Release-year windows offered in the sheet.
///
/// Presets rather than a dual-thumb range slider: SwiftUI has no range control,
/// and a hand-rolled one is a lot of gesture code for a filter most people set
/// once. The underlying model takes any `ClosedRange<Int>`, so a slider can
/// replace this later without touching the query layer.
private enum YearPreset: String, CaseIterable, Identifiable {
    case any, last2, last5, decade2010, decade2000, before2000

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "Any"
        case .last2: return "Last 2 years"
        case .last5: return "Last 5 years"
        case .decade2010: return "2010s"
        case .decade2000: return "2000s"
        case .before2000: return "Before 2000"
        }
    }

    var range: ClosedRange<Int>? {
        let now = BrowseCatalog.yearBounds.upperBound
        switch self {
        case .any: return nil
        case .last2: return (now - 1)...now
        case .last5: return (now - 4)...now
        case .decade2010: return 2010...2019
        case .decade2000: return 2000...2009
        case .before2000: return BrowseCatalog.yearBounds.lowerBound...1999
        }
    }

    static func matching(_ range: ClosedRange<Int>?) -> YearPreset {
        allCases.first { $0.range == range } ?? .any
    }
}

// MARK: - Sheet

struct BrowseFilterSheet: View {
    let filters: BrowseFilters
    var onApply: (BrowseFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: BrowseFilters
    @State private var previewCount: Int?
    @State private var isCounting = false
    @State private var countTask: Task<Void, Never>?

    init(filters: BrowseFilters, onApply: @escaping (BrowseFilters) -> Void) {
        self.filters = filters
        self.onApply = onApply
        _draft = State(initialValue: filters)
    }

    var body: some View {
        VStack(spacing: 0) {
            GsSheetHeader(title: "Filters") {
                Button("Reset") { reset() }
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.orange)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    typeGroup
                    genreGroup
                    servicesGroup
                    yearGroup
                    ratingGroup
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }

            applyButton
        }
        .sheetSurface(.base)
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .onAppear { scheduleCount() }
        .onChange(of: draft) { _, _ in scheduleCount() }
        .onDisappear { countTask?.cancel() }
    }

    // MARK: Groups

    private var typeGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLabel("Type")

            HStack(spacing: 3) {
                ForEach(BrowseMediaType.allCases, id: \.rawValue) { type in
                    let isOn = draft.resolvedMediaType == type
                    Button {
                        guard draft.lockingGenre == nil else { return }
                        draft.mediaType = type
                    } label: {
                        Text(type.label)
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(isOn ? Color.navy : Color.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isOn ? Color.orange : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
            .opacity(draft.lockingGenre == nil ? 1 : 0.55)

            // Horror is film-only in TMDB and Anime is TV-only, so picking
            // either pins Type instead of quietly returning an empty grid.
            if let reason = draft.lockingGenre?.lockReason {
                Text(reason)
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
    }

    private var genreGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLabel("Genre")
            chipFlow(BrowseCatalog.genres.map(\.id)) { id in
                let genre = BrowseCatalog.genre(id)
                return ChipSpec(
                    label: genre?.name ?? id,
                    isOn: draft.genreIds.contains(id)
                ) {
                    if draft.genreIds.contains(id) {
                        // Never leave the grid genre-less; it is the subject.
                        guard draft.genreIds.count > 1 else { return }
                        draft.genreIds.remove(id)
                    } else {
                        draft.genreIds.insert(id)
                    }
                }
            }
        }
    }

    private var servicesGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupLabel("Where I can watch")
                .padding(.bottom, 4)

            toggleRow(
                title: "Only my services",
                detail: draft.providerIds.isEmpty ? nil : "\(draft.providerIds.count) connected",
                isOn: $draft.onlyMyServices,
                showsDivider: true
            )
            toggleRow(
                title: "Include free with ads",
                detail: nil,
                isOn: $draft.includeFreeWithAds,
                showsDivider: false
            )
        }
    }

    private var yearGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLabel("Release year")
            chipFlow(YearPreset.allCases.map(\.rawValue)) { raw in
                let preset = YearPreset(rawValue: raw) ?? .any
                return ChipSpec(
                    label: preset.label,
                    isOn: YearPreset.matching(draft.yearRange) == preset
                ) {
                    draft.yearRange = preset.range
                }
            }
        }
    }

    private var ratingGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLabel("Minimum rating")
            HStack(spacing: 8) {
                chip(label: "Any", isOn: draft.minRating == nil) { draft.minRating = nil }
                ForEach(BrowseCatalog.ratingOptions, id: \.self) { value in
                    chip(label: "★ \(Int(value))+", isOn: draft.minRating == value) {
                        draft.minRating = value
                    }
                }
            }
        }
    }

    // MARK: Apply

    private var applyButton: some View {
        Button {
            onApply(draft)
            dismiss()
        } label: {
            Text(applyTitle)
                .scaledFont(size: 15, weight: .bold)
                .foregroundStyle(hasResults ? Color.navy : Color.white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(hasResults ? Color.orange : Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasResults)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 30)
    }

    private var hasResults: Bool { (previewCount ?? 1) > 0 }

    private var applyTitle: String {
        if isCounting || previewCount == nil { return "Counting…" }
        guard let previewCount, previewCount > 0 else { return "No titles match" }
        return "Show \(previewCount.formatted()) titles"
    }

    /// Debounced so dragging through chips does not fire a request per tap.
    private func scheduleCount() {
        countTask?.cancel()
        isCounting = true
        let snapshot = draft
        countTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let page = try? await TMDBService.shared.discoverBrowse(snapshot, page: 1)
            guard !Task.isCancelled else { return }
            previewCount = page?.totalResults ?? 0
            isCounting = false
        }
    }

    private func reset() {
        var cleared = BrowseFilters(providerIds: draft.providerIds)
        cleared.genreIds = draft.genreIds
        draft = cleared
    }

    // MARK: Pieces

    private struct ChipSpec {
        let label: String
        let isOn: Bool
        let action: () -> Void
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .scaledFont(size: 11, weight: .bold)
            .tracking(1.2)
            .foregroundStyle(Color.white.opacity(0.42))
    }

    private func chipFlow(_ ids: [String], spec: @escaping (String) -> ChipSpec) -> some View {
        // Wrapping chip rows. `Layout` would be tidier, but a fixed two-column
        // wrap keeps the sheet height predictable across Dynamic Type sizes.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ids.chunked(2).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { id in
                        let s = spec(id)
                        chip(label: s.label, isOn: s.isOn, action: s.action)
                            .frame(maxWidth: .infinity)
                    }
                    if row.count == 1 { Spacer().frame(maxWidth: .infinity) }
                }
            }
        }
    }

    private func chip(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(isOn ? Color.navy : Color.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(isOn ? Color.orange : Color.white.opacity(0.07))
                )
                .overlay(
                    Capsule().stroke(
                        isOn ? Color.orange : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(
        title: String,
        detail: String?,
        isOn: Binding<Bool>,
        showsDivider: Bool
    ) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: isOn) {
                HStack(spacing: 6) {
                    Text(title)
                        .scaledFont(size: 14)
                        .foregroundStyle(.white)
                    if let detail {
                        Text("· \(detail)")
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
            }
            .tint(Color.orange)
            .padding(.vertical, 11)

            if showsDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)
            }
        }
    }
}
