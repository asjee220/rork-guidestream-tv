//
//  ServiceTile.swift
//  GuideStreamTVTV
//
//  The selectable service tile used by the onboarding "Which services do you
//  have?" grid and by Connected Services.
//
//  It used to draw a flat brand-coloured card with the first letter of the
//  service name, because the tvOS catalog only carries id, name and colour.
//  That put a screen of "N", "P", "D", "M" in front of the viewer where the
//  phone shows real word-marks. TVServiceBrandMark already ports the phone's
//  marks — Netflix's serif N, "prime video" on two lines, Disney+, max, tv+ —
//  so the two platforms now render the same thing from the same data.
//
//  Two independent cues, as everywhere else in the target: selection is the
//  orange ring and check badge, focus is a white outline and a small lift.
//  A tile can be either, both, or neither, and they never read as the same
//  state. `.plain` is deliberately not used — on tvOS it lays a white slab
//  over the whole tile on focus.
//

import SwiftUI

struct ServiceTile: View {
    let service: StreamingService
    let isSelected: Bool
    /// Side of the square mark. Ten-foot default; onboarding may pass its own.
    var tileSize: CGFloat = 170
    let onTap: () -> Void

    @FocusState private var isFocused: Bool

    private let corner: CGFloat = 18

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 14) {
                TVServiceBrandMark(
                    providerName: service.name,
                    size: tileSize,
                    catalogId: service.id,
                    cornerRadius: corner
                )
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(ringColor, lineWidth: ringWidth)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        ZStack {
                            Circle().fill(Color.orange)
                                .frame(width: 34, height: 34)
                            Image(systemName: "checkmark")
                                .font(.system(size: 17, weight: .black))
                                .foregroundStyle(.black)
                        }
                        .offset(x: 9, y: -9)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .shadow(
                    color: isSelected ? Color.orange.opacity(0.45) : .clear,
                    radius: 18, x: 0, y: 0
                )
                .scaleEffect(isFocused ? 1.06 : 1.0)

                Text(service.name)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isFocused ? .white : Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: tileSize + 24)
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
    }

    /// Focus wins the ring, because it is the transient state the viewer is
    /// steering; selection keeps the badge either way, so nothing is lost.
    private var ringColor: Color {
        if isFocused { return .white }
        return isSelected ? .orange : .clear
    }

    private var ringWidth: CGFloat {
        if isFocused { return 3 }
        return isSelected ? 3 : 0
    }
}
