//
//  ServicesPill.swift
//  GuideStreamTV
//
//  Orange-outlined pill that sits to the right of the GuideStream TV wordmark
//  in the top bar on Home and Sports. Shows the user's first three selected
//  services as stacked overlapping mini-icons with a small counter badge in
//  the top-right corner. Tapping the pill opens `ServicesBottomSheet`, which
//  contains the same content as the onboarding "Which services do you have?"
//  step so users can edit their list at any time.
//

import SwiftUI
import UIKit

struct ServicesPill: View {
    /// Selected service ids in catalogue order. The pill renders the first
    /// three as overlapping icons and the total in the counter badge.
    let serviceIds: [String]
    let onTap: () -> Void

    private var topServices: [StreamingService] {
        Array(serviceIds.compactMap { StreamingCatalog.service(for: $0) }.prefix(3))
    }

    private let iconDiameter: CGFloat = 22
    /// Horizontal stride between overlapping icons. Smaller = more overlap.
    private let stride: CGFloat = 13

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 8) {
                stackedIcons
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
                counterBadge
                    .offset(x: 6, y: -7)
            }
            .shadow(color: Color.orange.opacity(0.25), radius: 8, x: 0, y: 0)
        }
        .buttonStyle(ServicesPillButtonStyle())
        .accessibilityLabel("My services. \(serviceIds.count) selected. Tap to edit.")
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
            .shadow(color: Color.orange.opacity(0.45), radius: 4, x: 0, y: 0)
    }

    private func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTap()
    }
}

private struct ServicesPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Pill") {
    ZStack {
        Color.navy.ignoresSafeArea()
        ServicesPill(
            serviceIds: ["netflix", "hbo", "disney", "hulu", "prime"],
            onTap: {}
        )
    }
}
