//
//  TabBar.swift
//  GuideStreamTV
//

import SwiftUI

enum AppTab: Int, CaseIterable, Hashable {
    case home, sports, ask, reels, profile

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .sports: return "soccerball"
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

    var body: some View {
        HStack(spacing: 0) {
            tabItem(.home)
            tabItem(.sports)
            askButton
            tabItem(.reels)
            tabItem(.profile)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(height: 74)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.55), radius: 28, y: 16)
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) {
                isGlowExpanded = true
            }
        }
    }

    @ViewBuilder
    private func tabItem(_ tab: AppTab) -> some View {
        let selected = selection == tab
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.guideBody(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? Color(hex: "F5821F") : Color.white.opacity(0.35))
                    .symbolEffect(.bounce, value: selected)
                Text(tab.title)
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
        let selected = selection == .ask
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selection = .ask
            }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(isGlowExpanded ? 0.50 : 0.30))
                        .frame(width: isGlowExpanded ? 84 : 62, height: isGlowExpanded ? 84 : 62)
                        .blur(radius: isGlowExpanded ? 22 : 14)
                    Circle()
                        .stroke(Color.orange.opacity(isGlowExpanded ? 0.34 : 0.10), lineWidth: 1.5)
                        .frame(width: isGlowExpanded ? 72 : 58, height: isGlowExpanded ? 72 : 58)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color(red: 0.95, green: 0.42, blue: 0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.orange.opacity(0.55), radius: 18, y: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.30), lineWidth: 1)
                        )
                    Image(systemName: "sparkles")
                        .font(.guideHeading(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(selected ? 1.12 : 1.0)
                        .symbolEffect(.pulse, value: selected)
                }
                .frame(width: 84, height: 60)

                Text("Ask")
                    .font(.guideBody(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(selected ? 1.0 : 0.72))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .offset(y: -14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Ask Stream")
    }
}
