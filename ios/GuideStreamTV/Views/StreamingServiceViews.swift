//
//  StreamingServiceViews.swift
//  GuideStreamTV
//
//  Shared SwiftUI views for rendering streaming-service brands. Used by the
//  onboarding "Which services do you have?" grid AND the services pill /
//  bottom sheet so brand styling stays consistent everywhere.
//

import SwiftUI

// MARK: - Big onboarding tile

struct ServiceTile: View {
    let service: StreamingService
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(service.bg)

                    ServiceBrandContent(display: service.display, size: .tile)
                        .padding(8)
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isSelected ? service.glow : Color.white.opacity(0.06),
                            lineWidth: isSelected ? 3 : 1
                        )
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        ZStack {
                            Circle().fill(service.glow)
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .scaledFont(size: 11, weight: .black)
                                .foregroundStyle(service.bg == .black ? .white : .black)
                        }
                        .offset(x: 6, y: -6)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .shadow(
                    color: isSelected ? service.glow.opacity(0.55) : .clear,
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

// MARK: - Mini icon (used inside the header pill)

/// A circular service mini-icon. Renders the same brand glyph as the big
/// tile but at small sizes for stacking. The `size` parameter is the diameter.
struct ServiceMiniIcon: View {
    let service: StreamingService
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(service.bg)
            .frame(width: size, height: size)
            .overlay {
                ServiceBrandContent(display: service.display, size: .mini(size))
                    .padding(size * 0.14)
            }
            .clipShape(Circle())
    }
}

// MARK: - Shared brand-content rendering

enum ServiceBrandSize {
    /// Big onboarding tile (square ~96-110pt).
    case tile
    /// Mini circular icon. The associated value is the diameter.
    case mini(CGFloat)
}

struct ServiceBrandContent: View {
    let display: StreamingServiceDisplay
    let size: ServiceBrandSize

    var body: some View {
        switch display {
        case .text(let str, let color, let weight, let design):
            Text(str)
                .scaledFont(size: textSize(for: str), weight: weight, design: design)
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .lineLimit(str.contains("\n") ? 2 : 1)
        case .symbol(let name, let color):
            Image(systemName: name)
                .scaledFont(size: symbolSize, weight: .bold)
                .foregroundStyle(color)
        case .symbolText(let symbol, let suffix, let color):
            HStack(spacing: 2) {
                Image(systemName: symbol)
                    .scaledFont(size: symbolSize * 0.75, weight: .bold)
                Text(suffix)
                    .scaledFont(size: symbolSize * 0.62, weight: .bold)
            }
            .foregroundStyle(color)
        case .star:
            Image(systemName: "star.fill")
                .scaledFont(size: symbolSize)
                .foregroundStyle(Color(red: 0xFF/255, green: 0xC8/255, blue: 0x1E/255))
        }
    }

    /// Heuristic text size — short monograms scale bigger, long word-marks shrink.
    private func textSize(for str: String) -> CGFloat {
        switch size {
        case .tile:
            if str.count <= 1 { return 36 }
            if str.count <= 4 { return 26 }
            if str.contains("\n") { return 16 }
            return 14
        case .mini(let d):
            let base = d * 0.55
            if str.count <= 1 { return d * 0.55 }
            if str.count <= 3 { return base }
            if str.contains("\n") { return d * 0.30 }
            if str.count <= 5 { return d * 0.36 }
            return d * 0.28
        }
    }

    private var symbolSize: CGFloat {
        switch size {
        case .tile: return 32
        case .mini(let d): return d * 0.55
        }
    }
}
