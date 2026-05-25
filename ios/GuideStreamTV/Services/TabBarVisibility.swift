//
//  TabBarVisibility.swift
//  GuideStreamTV
//
//  Shared observable that drives the FloatingTabBar show/hide animation
//  based on scroll direction across the app's root tab screens.
//

import SwiftUI

@Observable
final class TabBarVisibility {
    var isVisible: Bool = true

    /// Last observed scroll offset (y). Positive means scrolled away from top.
    private var lastOffset: CGFloat = 0
    /// Accumulated delta in one direction; we only flip when it crosses the threshold.
    private var accumulatedDelta: CGFloat = 0
    /// How many points of movement in a single direction are needed to toggle.
    private let threshold: CGFloat = 12

    func update(offset: CGFloat) {
        let delta = offset - lastOffset
        lastOffset = offset

        // Always show at (or above) the top of content.
        if offset <= 0 {
            accumulatedDelta = 0
            setVisible(true)
            return
        }

        // Ignore tiny jitter.
        if abs(delta) < 0.5 { return }

        // Reset accumulator when direction changes.
        if (delta > 0 && accumulatedDelta < 0) || (delta < 0 && accumulatedDelta > 0) {
            accumulatedDelta = 0
        }
        accumulatedDelta += delta

        if accumulatedDelta > threshold {
            setVisible(false)
        } else if accumulatedDelta < -threshold {
            setVisible(true)
        }
    }

    private func setVisible(_ newValue: Bool) {
        guard isVisible != newValue else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            isVisible = newValue
        }
    }

    /// Reset to the default visible state — call when a tab is swapped in.
    func reset() {
        lastOffset = 0
        accumulatedDelta = 0
        if !isVisible {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                isVisible = true
            }
        }
    }

    /// Force-hide with animation — used for full-screen consumption surfaces (Reels).
    func hide() {
        lastOffset = 0
        accumulatedDelta = 0
        setVisible(false)
    }

    /// Force-show with animation.
    func show() {
        lastOffset = 0
        accumulatedDelta = 0
        setVisible(true)
    }
}

// MARK: - Environment plumbing

private struct TabBarVisibilityKey: EnvironmentKey {
    static let defaultValue: TabBarVisibility = TabBarVisibility()
}

extension EnvironmentValues {
    var tabBarVisibility: TabBarVisibility {
        get { self[TabBarVisibilityKey.self] }
        set { self[TabBarVisibilityKey.self] = newValue }
    }
}

// MARK: - Scroll tracking modifier

extension View {
    /// Attach to a vertical `ScrollView` whose offset should drive the floating
    /// tab bar visibility. Uses `onScrollGeometryChange` (iOS 18+).
    func tracksTabBarVisibility() -> some View {
        modifier(TracksTabBarVisibilityModifier())
    }
}

private struct TracksTabBarVisibilityModifier: ViewModifier {
    @Environment(\.tabBarVisibility) private var visibility

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, newValue in
                visibility.update(offset: newValue)
            }
    }
}
