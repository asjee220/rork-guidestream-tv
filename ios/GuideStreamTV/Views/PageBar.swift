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
//  Watch List, so a change to the bar reaches all three.
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

            Button(action: onProfile) {
                AvatarRing(
                    initials: initials,
                    size: avatarDiameter,
                    fontWeight: .semibold,
                    avatar: auth.avatar
                )
            }
            .buttonStyle(.plain)
            .padding(.leading, avatarLeadingGap)
            .accessibilityLabel("Profile")
        }
        .padding(.horizontal, 12)
        .frame(height: 55)
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
