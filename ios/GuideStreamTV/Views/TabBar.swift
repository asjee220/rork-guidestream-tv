//
//  TabBar.swift
//  GuideStreamTV
//

import SwiftUI

private let reelsBadgeRingColor = Color(red: 0x0A/255, green: 0x12/255, blue: 0x1B/255)

enum AppTab: Int, CaseIterable, Hashable {
    case home, sports, ask, reels, profile

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .sports: return "american.football.fill"
        case .ask: return "sparkles"
        case .reels: return "play.square.stack.fill"
        case .profile: return "person.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .sports: return "Sports"
        case .ask: return "Ask"
        case .reels: return "Reels"
        case .profile: return "Profile"
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @State private var isGlowExpanded: Bool = false
    @State private var coachMark = CoachMarkManager.shared
    @State private var reelsBadge = ReelsBadgeService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            // Glass pill with four tabs — Home, Reels, Sports, Profile
            HStack(spacing: 0) {
                tabItem(.home)
                tabItem(.reels)
                    .anchorPreference(key: CoachMarkAnchorKey.self, value: .bounds) {
                        ["reels": $0]
                    }
                tabItem(.sports)
                    .anchorPreference(key: CoachMarkAnchorKey.self, value: .bounds) {
                        ["sports": $0]
                    }
                tabItem(.profile)
            }
            .padding(.horizontal, 6)
            .frame(height: 64)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 28, y: 16)

            // Detached circular Ask FAB
            askButton
                .anchorPreference(key: CoachMarkAnchorKey.self, value: .bounds) {
                    ["ask": $0]
                }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) {
                isGlowExpanded = true
            }
        }
    }

    @ViewBuilder
    private func tabItem(_ tab: AppTab) -> some View {
        let selected = selection == tab
        let showBadge = tab == .reels && reelsBadge.hasUnseen && !selected
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.symbol)
                        .font(.guideBody(size: 22, weight: .semibold))
                        .foregroundStyle(selected ? Color(hex: "F5821F") : Color.white.opacity(0.35))
                        .symbolEffect(.bounce, value: selected)

                    if showBadge {
                        Circle()
                            .fill(reelsBadgeRingColor)
                            .frame(width: 13, height: 13)
                            .overlay(
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 9, height: 9)
                            )
                            .offset(x: 5, y: -4)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .scale.combined(with: .opacity)
                            )
                            .animation(
                                reduceMotion
                                    ? nil
                                    : .spring(response: 0.34, dampingFraction: 0.62),
                                value: reelsBadge.hasUnseen
                            )
                    }
                }
                Text(LocalizedStringKey(tab.title))
                    .font(.guideBody(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? Color.white.opacity(0.92) : Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Circle()
                    .fill(selected ? Color.orange : .clear)
                    .frame(width: 4, height: 4)
                    .shadow(color: selected ? Color.orange : .clear, radius: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var askButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selection = .ask
            }
        } label: {
            ZStack {
                // Subtle pulsing glow behind the FAB
                Circle()
                    .fill(Color.orange.opacity(isGlowExpanded ? 0.24 : 0.08))
                    .frame(width: isGlowExpanded ? 66 : 54, height: isGlowExpanded ? 66 : 54)
                    .blur(radius: 9)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color(red: 0.95, green: 0.42, blue: 0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 54, height: 54)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.30), lineWidth: 1)
                    )

                Image(systemName: "sparkles")
                    .font(.guideHeading(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 54, height: 54)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Stream")
    }
}
