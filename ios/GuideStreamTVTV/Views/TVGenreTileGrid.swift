//
//  TVGenreTileGrid.swift
//  GuideStreamTVTV
//
//  The browse landing's genre picker: the ten genres from
//  Shared/BrowseFilters.swift laid out five across, two rows, so every one
//  is on screen without scrolling. The phone fetches artwork per genre;
//  here each tile carries its own brand gradient, which never blanks and
//  needs no extra network call on a screen the viewer is only passing
//  through.
//

import SwiftUI

/// Brand gradient per genre id. Keyed off BrowseCatalog ids, so adding a
/// genre there without adding a gradient here still renders — it falls back
/// to the neutral pair.
enum TVGenreTint {
    static func colors(for id: String) -> [Color] {
        switch id {
        case "crime":         return [Color(red: 0.23, green: 0.12, blue: 0.17), Color(red: 0.56, green: 0.17, blue: 0.28)]
        case "scifi":         return [Color(red: 0.05, green: 0.16, blue: 0.25), Color(red: 0.10, green: 0.44, blue: 0.91)]
        case "horror":        return [Color(red: 0.16, green: 0.05, blue: 0.07), Color(red: 0.70, green: 0.13, blue: 0.17)]
        case "anime":         return [Color(red: 0.17, green: 0.09, blue: 0.25), Color(red: 0.48, green: 0.25, blue: 0.71)]
        case "comedy":        return [Color(red: 0.23, green: 0.17, blue: 0.05), Color(red: 0.88, green: 0.64, blue: 0.16)]
        case "drama":         return [Color(red: 0.07, green: 0.15, blue: 0.21), Color(red: 0.21, green: 0.43, blue: 0.55)]
        case "action":        return [Color(red: 0.23, green: 0.11, blue: 0.03), TVTheme.orange]
        case "documentary":   return [Color(red: 0.06, green: 0.16, blue: 0.14), TVTheme.newsGreen]
        case "romance":       return [Color(red: 0.20, green: 0.07, blue: 0.16), Color(red: 0.76, green: 0.28, blue: 0.56)]
        case "international": return [Color(red: 0.06, green: 0.12, blue: 0.18), Color(red: 0.18, green: 0.36, blue: 0.54)]
        default:              return [TVTheme.surface, TVTheme.surfaceElevated]
        }
    }
}

struct TVGenreTileGrid: View {
    let onSelect: (BrowseGenre) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 26), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 26) {
            ForEach(BrowseCatalog.genres) { genre in
                TVGenreTile(genre: genre) { onSelect(genre) }
            }
        }
    }
}

private struct TVGenreTile: View {
    let genre: BrowseGenre
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: TVGenreTint.colors(for: genre.id),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [Color.black.opacity(0.72), Color.black.opacity(0.0)],
                    startPoint: .bottom,
                    endPoint: .center
                )

                Text(genre.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(20)
                    .shadow(color: .black.opacity(0.7), radius: 12)
            }
            .frame(height: 190)
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isFocused ? TVTheme.orange : Color.clear, lineWidth: 4)
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .focusEffectDisabled()
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .accessibilityLabel("Browse \(genre.name)")
    }
}
