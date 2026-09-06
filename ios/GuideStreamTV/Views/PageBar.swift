//
//  PageBar.swift
//  GuideStreamTV
//
//  The pinned top bar: wordmark on the left, services pill and profile avatar
//  on the right.
//
//  It used to be a private struct inside HomeView, with Sports keeping its own
//  hand-rolled copy of the same HStack. That is how the two drifted — Sports
//  never got the avatar. One internal view now serves Home, Sports and the
//  Watchlist, so a change to the bar reaches all three.
//

import SwiftUI

struct PageBar: View {
    let selectedServiceIds: [String]
    let onServicesPill: () -> Void
    let onProfile: () -> Void
    /// Sports shows a spinner here while a background refresh is in flight.
    var isRefreshing: Bool = false
    /// Only Home runs the coach-mark tour, and only Home should publish the
    /// anchor it measures the "services" step against.
    var publishesCoachAnchor: Bool = false

    @State private var auth = AuthViewModel.shared

    /// Matches the services pill's height exactly: its icons are 22pt with 5pt
    /// of padding above and below. The avatar is the pill's visual partner, so
    /// the two read as one control group rather than two sizes.
    private let avatarDiameter: CGFloat = 32

    /// Breathing room between the pill and the avatar, on top of the HStack's
    /// own 10pt. They are different controls and shouldn't look joined.
    private let avatarLeadingGap: CGFloat = 8

    /// Tappable area around the avatar. Larger than the ring it contains, on
    /// purpose: 32pt is a small thing to hit at the corner of the screen.
    private let avatarHitTarget: CGFloat = 48

    var body: some View {
        HStack(spacing: 10) {
            BrandWordmark(wordmarkSize: .nav)
            Spacer()

            if isRefreshing {
                ProgressView()
                    .tint(Color.orange)
                    .scaleEffect(0.8)
            }

            if !selectedServiceIds.isEmpty {
                servicesPill
            }

            profileButton
        }
        .padding(.horizontal, 12)
        .frame(height: 55)
    }

    /// The avatar, plus the coach-mark anchor when Home is running the tour.
    /// The anchor is published on the drawn ring, not on the button: the
    /// button's frame is the 48pt hit target plus an 8pt leading gap, so
    /// measuring it put an oversized spotlight circle slightly left of the
    /// avatar it was meant to be highlighting.
    @ViewBuilder
    private var avatarRing: some View {
        let ring = AvatarRing(
            initials: initials,
            size: avatarDiameter,
            fontWeight: .semibold,
            avatar: auth.avatar
        )
        .frame(width: avatarDiameter, height: avatarDiameter)

        if publishesCoachAnchor {
            ring.anchorPreference(key: CoachMarkAnchorKey.self, value: .bounds) {
                ["profile": $0]
            }
        } else {
            ring
        }
    }

    private var profileButton: some View {
        Button(action: onProfile) {
            avatarRing
                // The ring draws at 32 with a soft blurred halo around it, and
                // a blurred shape is not a reliable hit target. An explicit
                // frame plus a rectangular content shape gives the button a
                // solid 48pt target — above the 44pt minimum — without
                // changing anything that is drawn.
                .frame(width: avatarHitTarget, height: avatarHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, avatarLeadingGap)
        .accessibilityLabel("Profile")
    }

    @ViewBuilder
    private var servicesPill: some View {
        if publishesCoachAnchor {
            ServicesPill(serviceIds: selectedServiceIds, onTap: onServicesPill)
                .anchorPreference(key: CoachMarkAnchorKey.self, value: .bounds) {
                    ["services": $0]
                }
        } else {
            ServicesPill(serviceIds: selectedServiceIds, onTap: onServicesPill)
        }
    }

    private var initials: String {
        ProfileView.initials(
            firstName: auth.firstName,
            lastName: auth.lastName,
            fallbackName: auth.displayName ?? "",
            isGuest: auth.isGuest,
            isAuthenticated: auth.isAuthenticated
        )
    }
}
