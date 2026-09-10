//
//  ServicesPill.swift
//  GuideStreamTVTV
//
//  tvOS port of the iOS `ServicesPill` — the orange-outlined pill in the
//  top bar that shows the user's first three selected services as stacked
//  mini-icons with a counter badge. Pressing it opens the services sheet
//  so users can edit their list. The iOS file lives at:
//  ios/GuideStreamTV/Views/ServicesPill.swift
//
//  GUI-101: the empty state is a pill, not an absence. Home and Sports used to
//  hide this control entirely when nothing was selected, which left a TV viewer
//  who skipped the services step with no route to the editor on either screen.
//  It now draws three dashed placeholder rings and the word "Add" in the same
//  place and silhouette as the filled pill.
//

import SwiftUI

struct ServicesPill: View {
    let serviceIds: [String]
    let onTap: () -> Void

    private var topServices: [StreamingService] {
        Array(serviceIds.compactMap { id in
            StreamingCatalog.all.first { $0.id == id }
        }.prefix(3))
    }

    private let iconDiameter: CGFloat = 22
    private let stride: CGFloat = 13

    /// No services chosen yet — the pill switches to its invitation state.
    private var isEmpty: Bool { serviceIds.isEmpty }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if isEmpty {
                    ghostIcons
                    Text("Add")
                        .scaledFont(size: 11, weight: .heavy)
                        .foregroundStyle(Color.orange)
                } else {
                    stackedIcons
                }
                Image(systemName: "chevron.down")
                    .scaledFont(size: 9, weight: .bold)
                    .foregroundStyle(Color.orange.opacity(0.75))
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.orange.opacity(0.10))
            )
            .overlay(
                Capsule().stroke(Color.orange, lineWidth: 1.4)
            )
            .overlay(alignment: .topTrailing) {
                // No badge in the empty state — a "0" reads as a broken
                // counter, and the dashed rings already say "nothing here".
                if !isEmpty {
                    counterBadge.offset(x: 6, y: -7)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isEmpty
                ? "Add your services. None selected yet. Press to choose."
                : "My services. \(serviceIds.count) selected. Press to edit."
        )
    }

    /// Three dashed rings occupying exactly the space the real icons would,
    /// filled with the bar's own navy so they overlap the way the real stack
    /// does.
    private var ghostIcons: some View {
        let count = 3
        let width = stride * CGFloat(count - 1) + iconDiameter
        return ZStack(alignment: .leading) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(Color.navy)
                    .frame(width: iconDiameter, height: iconDiameter)
                    .overlay(
                        Circle().strokeBorder(
                            Color.orange.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5])
                        )
                    )
                    .offset(x: stride * CGFloat(index))
                    .zIndex(Double(count - index))
            }
        }
        .frame(width: width, height: iconDiameter, alignment: .leading)
    }

    private var stackedIcons: some View {
        let icons = topServices
        let width = stride * CGFloat(max(icons.count, 1) - 1) + iconDiameter
        return ZStack(alignment: .leading) {
            ForEach(Array(icons.enumerated()), id: \.element.id) { index, service in
                ServiceMiniIcon(service: service, size: iconDiameter)
                    .overlay(
                        Circle().stroke(Color.navy, lineWidth: 1.5)
                    )
                    .offset(x: stride * CGFloat(index))
                    .zIndex(Double(icons.count - index))
            }
        }
        .frame(width: width, height: iconDiameter, alignment: .leading)
    }

    private var counterBadge: some View {
        Text("\(serviceIds.count)")
            .scaledFont(size: 9, weight: .black)
            .foregroundStyle(.white)
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, 4)
            .background(
                Capsule().fill(Color.orange)
            )
            .overlay(
                Capsule().stroke(Color.navy, lineWidth: 1.5)
            )
    }
}

// MARK: - ServiceMiniIcon

/// Circular service mini-icon used inside the pill and other compact
/// service-row contexts. The tvOS catalog is simpler than iOS (just an
/// `id`, `name`, and `color`) so this renders a flat colored circle with
/// the first letter of the service name as the glyph.
struct ServiceMiniIcon: View {
    let service: StreamingService
    var size: CGFloat = 22

    private var glyph: String {
        String(service.name.prefix(1)).uppercased()
    }

    var body: some View {
        Circle()
            .fill(service.color)
            .frame(width: size, height: size)
            .overlay {
                Text(glyph)
                    .scaledFont(size: size * 0.55, weight: .black)
                    .foregroundStyle(glyphColor)
            }
    }

    /// Render light glyphs on dark service backgrounds and vice versa.
    /// The catalog uses a few near-black colors (e.g. Apple TV+, Peacock,
    /// Starz) where a black glyph would be invisible.
    private var glyphColor: Color {
        switch service.id {
        case "appletv", "peacock", "starz":
            return .white
        default:
            return .white
        }
    }
}
