//
//  CoachMarkOverlay.swift
//  GuideStreamTV
//
//  Spotlight overlay that dims the screen, cuts holes around one or two
//  real UI elements, and shows a callout card explaining them. Uses a
//  PreferenceKey carrying [String: Anchor<CGRect>] for target measurement.
//

import SwiftUI

// MARK: - PreferenceKey for anchor-based target measurement

struct CoachMarkAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, b in b })
    }
}

// MARK: - Overlay view

struct CoachMarkOverlay: View {
    let manager: CoachMarkManager

    var body: some View {
        GeometryReader { geo in
            let screen = geo.frame(in: .global)
            if manager.isShowing, let mark = manager.currentMark {
                overlayContent(mark: mark, screen: screen)
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(manager.isShowing)
        .animation(.easeInOut(duration: 0.25), value: manager.isShowing)
    }

    // MARK: - Scrim + cutouts + card

    @ViewBuilder
    private func overlayContent(mark: CoachMark, screen: CGRect) -> some View {
        let rects = manager.measuredRects
        let validRects = mark.targetKeys.compactMap { key -> (String, CGRect)? in
            guard let r = rects[key], !r.isEmpty else { return nil }
            return (key, r)
        }

        if validRects.isEmpty || !manager.scrollSettled {
            // Waiting for scroll to settle or no valid frames — show nothing
            Color.clear
                .onAppear {
                    if validRects.isEmpty && manager.scrollSettled {
                        let markKey = mark.key
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // Guard against the measurement task arriving in the
                            // meantime and populating rects for this same mark.
                            guard manager.currentMark?.key == markKey else { return }
                            guard let current = manager.currentMark,
                                  current.targetKeys.contains(where: {
                                      manager.measuredRects[$0]?.isEmpty ?? true
                                  }) else {
                                return
                            }
                            manager.skipUnmeasurableMark()
                        }
                    }
                }
        } else {
            let cutoutRects = validRects.map { $0.1 }
            ZStack {
                scrimWithHoles(rects: cutoutRects, mark: mark, screen: screen)

                ForEach(Array(cutoutRects.indices), id: \.self) { idx in
                    pulseRing(rect: cutoutRects[idx], isCircular: mark.isCircular)
                }

                if let firstKey = mark.targetKeys.first,
                   let firstRect = rects[firstKey], !firstRect.isEmpty {
                    calloutCard(
                        mark: mark,
                        anchorRect: firstRect,
                        allRects: cutoutRects,
                        screen: screen,
                        index: manager.currentIndex,
                        total: manager.activeTour.count
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                manager.advance()
            }
        }
    }

    // MARK: - Scrim with holes (single mask, no double-opacity)

    private func scrimWithHoles(rects: [CGRect], mark: CoachMark, screen: CGRect) -> some View {
        Canvas { context, size in
            // Fill entire screen with scrim
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color.navy.opacity(0.57)))
            // Cut all holes from a single mask
            context.blendMode = .destinationOut
            for rect in rects {
                let expanded = rect.insetBy(dx: -8, dy: -8)
                if mark.isCircular {
                    let dim = max(expanded.width, expanded.height)
                    let cx = expanded.midX
                    let cy = expanded.midY
                    let r = dim / 2
                    context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                                 with: .color(.white))
                } else {
                    context.fill(RoundedRectangle(cornerRadius: 14).path(in: expanded),
                                 with: .color(.white))
                }
            }
            context.blendMode = .normal
        }
        .frame(width: screen.width, height: screen.height)
        .ignoresSafeArea()
    }

    // MARK: - Pulse ring (opacity 0.9 → 0.15 → 0.9 over 1.7s)

    @ViewBuilder
    private func pulseRing(rect: CGRect, isCircular: Bool) -> some View {
        let expanded = rect.insetBy(dx: -8, dy: -8)
        PulseRingView(expanded: expanded, isCircular: isCircular)
            .ignoresSafeArea()
    }

    // MARK: - Callout card

    @ViewBuilder
    private func calloutCard(
        mark: CoachMark,
        anchorRect: CGRect,
        allRects: [CGRect],
        screen: CGRect,
        index: Int,
        total: Int
    ) -> some View {
        let lowestBottom = allRects.map { $0.maxY }.max() ?? anchorRect.maxY
        let highestTop = allRects.map { $0.minY }.min() ?? anchorRect.minY
        let midScreen = screen.midY
        let cardWidth: CGFloat = 230

        // Position: 12pt below lowest cutout if above midpoint,
        // otherwise 12pt above highest cutout
        let belowCard: Bool = lowestBottom < midScreen

        VStack(alignment: .leading, spacing: 0) {
            Text(mark.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.navy)

            Text(mark.body)
                .font(.system(size: 12))
                .foregroundStyle(Color.navy.opacity(0.72))
                .lineSpacing(6) // 1.5 line height for 12pt
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            HStack {
                HStack(spacing: 4) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle()
                            .fill(i == index ? Color.navy : Color.navy.opacity(0.30))
                            .frame(width: 5, height: 5)
                    }
                }
                Spacer()
                Text("Skip")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.navy.opacity(0.72))
                    .contentShape(Rectangle())
                    .onTapGesture { manager.skipTour() }
                Text(mark.isLastInTour ? "Done" : "Next")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.navy)
                    .padding(.leading, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { manager.advance() }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: cardWidth)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange))
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            GeometryReader { cardGeo in
                Color.clear.onAppear {
                    positionedCardSize = cardGeo.size
                }
                .onChange(of: cardGeo.size) { _, newSize in
                    positionedCardSize = newSize
                }
            }
        }
        .position(
            x: clampX(anchorRect: anchorRect, cardWidth: cardWidth, screen: screen),
            y: belowCard
                ? lowestBottom + 12 + (positionedCardSize.height / 2)
                : highestTop - 12 - (positionedCardSize.height / 2)
        )
        .ignoresSafeArea()
    }

    @State private var positionedCardSize: CGSize = .init(width: 230, height: 120)

    private func clampX(anchorRect: CGRect, cardWidth: CGFloat, screen: CGRect) -> CGFloat {
        var x = anchorRect.midX - cardWidth / 2
        x = max(10 + cardWidth / 2, x)
        x = min(screen.width - 10 - cardWidth / 2, x)
        return x
    }
}

// MARK: - Pulse ring with phase animation

private struct PulseRingView: View {
    let expanded: CGRect
    let isCircular: Bool
    @State private var pulse: Bool = false

    var body: some View {
        Group {
            if isCircular {
                let dim = max(expanded.width, expanded.height)
                let r = dim / 2
                Circle()
                    .stroke(Color.orange, lineWidth: 2)
                    .frame(width: r * 2, height: r * 2)
                    .position(x: expanded.midX, y: expanded.midY)
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.orange, lineWidth: 2)
                    .frame(width: expanded.width, height: expanded.height)
                    .position(x: expanded.midX, y: expanded.midY)
            }
        }
        .opacity(pulse ? 0.15 : 0.9)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
