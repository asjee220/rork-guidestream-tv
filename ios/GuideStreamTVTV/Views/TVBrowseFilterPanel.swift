//
//  TVBrowseFilterPanel.swift
//  GuideStreamTVTV
//
//  Trailing-edge filter panel for browse results. The phone puts these
//  controls in a grouped bottom sheet; a sheet rising from the bottom edge
//  is a touch idiom and costs a long focus journey on a remote, so on tvOS
//  the same groups live in a full-height panel reached by pressing right
//  from the grid. Results re-query live behind it, so the count moves while
//  the panel is still open.
//

import SwiftUI

struct TVBrowseFilterPanel: View {
    @Binding var filters: BrowseFilters
    let onClose: () -> Void

    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case reset
        case type(BrowseMediaType)
        case services
        case freeWithAds
        case rating(Int)
        case year(Int)
        case sort(BrowseSort)
    }

    /// Year windows offered, newest first. `nil` upper bound means "to now".
    private var yearOptions: [(label: String, range: ClosedRange<Int>?)] {
        let now = BrowseCatalog.yearBounds.upperBound
        return [
            ("Any", nil),
            ("2020s", 2020...now),
            ("2010s", 2010...2019),
            ("Older", BrowseCatalog.yearBounds.lowerBound...2009)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 38) {
                    typeGroup
                    availabilityGroup
                    ratingGroup
                    yearGroup
                    sortGroup
                    Color.clear.frame(height: 40)
                }
                .padding(.top, 38)
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 56)
        .frame(width: 560)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(TVTheme.bg.opacity(0.97))
        .overlay(alignment: .leading) {
            Rectangle().fill(TVTheme.hairline).frame(width: 1)
        }
        .focusSection()
        .onMoveCommand { direction in
            // Left from the panel hands focus back to the grid.
            if direction == .left { onClose() }
        }
        .onAppear { focus = .type(filters.mediaType) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Filters")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(TVTheme.textPrimary)

            Spacer()

            Button {
                filters = BrowseFilters(
                    genreIds: filters.genreIds,
                    providerIds: filters.providerIds
                )
            } label: {
                Text("Reset")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(focus == .reset ? TVTheme.textPrimary : TVTheme.orange)
            }
            .buttonStyle(TVPanelButtonStyle())
            .focused($focus, equals: .reset)
            .focusEffectDisabled()
            .disabled(filters.activeCount == 0)
            .opacity(filters.activeCount == 0 ? 0.35 : 1)
        }
    }

    // MARK: - Groups

    private var typeGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            groupLabel("Type")

            HStack(spacing: 10) {
                ForEach(BrowseMediaType.allCases, id: \.rawValue) { type in
                    segment(
                        title: type.label,
                        selected: filters.resolvedMediaType == type,
                        focused: focus == .type(type)
                    ) {
                        filters.mediaType = type
                    }
                    .focused($focus, equals: .type(type))
                }
            }
            .disabled(filters.lockingGenre != nil)
            .opacity(filters.lockingGenre != nil ? 0.5 : 1)

            if let reason = filters.lockingGenre?.lockReason {
                Text(reason)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(TVTheme.textSecondary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TVTheme.orange.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(TVTheme.orange).frame(width: 3)
                    }
                    .clipShape(.rect(cornerRadius: 8))
            }
        }
    }

    private var availabilityGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            groupLabel("Availability")

            toggleRow(
                title: "Only my services",
                isOn: filters.onlyMyServices,
                focused: focus == .services
            ) { filters.onlyMyServices.toggle() }
                .focused($focus, equals: .services)

            toggleRow(
                title: "Free with ads",
                isOn: filters.includeFreeWithAds,
                focused: focus == .freeWithAds
            ) { filters.includeFreeWithAds.toggle() }
                .focused($focus, equals: .freeWithAds)
        }
    }

    private var ratingGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            groupLabel("Minimum rating")

            HStack(spacing: 10) {
                segment(title: "Any", selected: filters.minRating == nil, focused: focus == .rating(0)) {
                    filters.minRating = nil
                }
                .focused($focus, equals: .rating(0))

                ForEach(Array(BrowseCatalog.ratingOptions.enumerated()), id: \.offset) { index, value in
                    segment(
                        title: "★ \(Int(value))+",
                        selected: filters.minRating == value,
                        focused: focus == .rating(index + 1)
                    ) {
                        filters.minRating = value
                    }
                    .focused($focus, equals: .rating(index + 1))
                }
            }
        }
    }

    private var yearGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            groupLabel("Release year")

            HStack(spacing: 10) {
                ForEach(Array(yearOptions.enumerated()), id: \.offset) { index, option in
                    segment(
                        title: option.label,
                        selected: filters.yearRange == option.range,
                        focused: focus == .year(index)
                    ) {
                        filters.yearRange = option.range
                    }
                    .focused($focus, equals: .year(index))
                }
            }
        }
    }

    private var sortGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            groupLabel("Sort by")

            VStack(spacing: 10) {
                ForEach(BrowseSort.allCases, id: \.rawValue) { option in
                    segment(
                        title: option.label,
                        selected: filters.sort == option,
                        focused: focus == .sort(option),
                        fullWidth: true
                    ) {
                        filters.sort = option
                    }
                    .focused($focus, equals: .sort(option))
                }
            }
        }
    }

    // MARK: - Pieces

    private func groupLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 14, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(TVTheme.textTertiary)
    }

    private func segment(
        title: String,
        selected: Bool,
        focused: Bool,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(selected ? TVTheme.bg : (focused ? TVTheme.textPrimary : TVTheme.textSecondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selected ? TVTheme.textPrimary : Color.white.opacity(0.05))
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(focused && !selected ? TVTheme.orange : Color.clear, lineWidth: 2)
                }
        }
        .buttonStyle(TVPanelButtonStyle())
        .focusEffectDisabled()
        .frame(maxWidth: fullWidth ? .infinity : nil)
    }

    private func toggleRow(
        title: String,
        isOn: Bool,
        focused: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(focused ? TVTheme.textPrimary : TVTheme.textSecondary)
                Spacer()
                Capsule()
                    .fill(isOn ? TVTheme.orange : Color.white.opacity(0.14))
                    .frame(width: 62, height: 34)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 26, height: 26)
                            .padding(4)
                    }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(focused ? Color.white.opacity(0.05) : .clear)
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(TVPanelButtonStyle())
        .focusEffectDisabled()
    }
}

/// Plain style with no system focus decoration — the panel draws its own,
/// same reasoning as TVMenuButtonStyle on the side menu.
struct TVPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
