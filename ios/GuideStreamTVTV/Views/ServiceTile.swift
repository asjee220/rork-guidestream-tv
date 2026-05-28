//
//  ServiceTile.swift
//  GuideStreamTVTV
//
//  tvOS port of the iOS `ServiceTile` — the large selectable tile used by
//  the onboarding "Which services do you have?" grid. The tvOS catalog is
//  simpler than iOS (just `id`, `name`, `color`) so this renders a flat
//  brand-colored card with the first letter of the service name as the
//  glyph, with a focus-friendly selection ring + checkmark badge.
//

import SwiftUI

struct ServiceTile: View {
    let service: StreamingService
    let isSelected: Bool
    let onTap: () -> Void

    private var glyph: String {
        String(service.name.prefix(1)).uppercased()
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(service.color)

                    Text(glyph)
                        .scaledFont(size: 36, weight: .black)
                        .foregroundStyle(.white)
                        .padding(8)
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isSelected ? Color.orange : Color.white.opacity(0.06),
                            lineWidth: isSelected ? 3 : 1
                        )
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        ZStack {
                            Circle().fill(Color.orange)
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .scaledFont(size: 11, weight: .black)
                                .foregroundStyle(.black)
                        }
                        .offset(x: 6, y: -6)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .shadow(
                    color: isSelected ? Color.orange.opacity(0.55) : .clear,
                    radius: 18, x: 0, y: 0
                )

                Text(service.name)
                    .font(.custom("SF Pro Text", size: 12).weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
    }
}
