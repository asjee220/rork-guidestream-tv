//
//  TVTabBarVisibility.swift
//  GuideStreamTVTV
//
//  tvOS no-op shim for the iOS floating-tab-bar visibility modifier. tvOS
//  uses the focus engine + standard TabView, so the scroll-driven show/hide
//  behavior from iOS isn't applicable. The modifier exists as a no-op so
//  shared view code compiles cleanly without `#if os(tvOS)` forks.
//

import SwiftUI

extension View {
    /// No-op on tvOS — iOS uses scroll offset to hide the floating tab bar.
    func tracksTabBarVisibility() -> some View {
        self
    }
}
