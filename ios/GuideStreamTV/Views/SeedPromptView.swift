//
//  SeedPromptView.swift
//  GuideStreamTV
//

import SwiftUI
import UIKit

/// Onboarding step 3 — introduces the "Seed Your List" concept and invites
/// the user to pick shows they follow so their Watch List is pre-populated.
struct SeedPromptView: View {
    let selectedServices: Set<String>
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(progress: 0.75)

            Spacer(minLength: 20)

            // Service badge row — dynamic from user's selected services (up to 3)
            HStack(spacing: 10) {
                ForEach(Array(selectedServices.sorted().prefix(3)), id: \.self) { service in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Self.serviceBadgeColor(service))
                            .frame(width: 48, height: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(service == "Paramount+" ? Color(red: 0.96, green: 0.51, blue: 0.12) : Color.clear, lineWidth: 2)
                            )
                        Text(Self.serviceBadgeAbbr(service))
                            .font(.custom("SF Pro Text", size: service == "Max" || service == "HBO Max" ? 9 : 13).weight(.heavy))
                            .foregroundStyle(service == "Hulu" ? Color.black : Color.white)
                    }
                }
            }

            Spacer(minLength: 16)

            // Headline
            Text("What are you watching right now?")
                .font(.custom("SF Pro Display", size: 28).weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 12)

            // Body copy
            Text("We found top shows across your connected services. Tap the ones you follow and we'll build your Watch List before you hit home.")
                .font(.custom("SF Pro Text", size: 14))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Spacer(minLength: 18)

            // Info card
            VStack(spacing: 12) {
                infoRow("Selected shows land in My Watch List")
                infoRow("New episodes trigger instant alerts")
                infoRow("Deep links take you straight there")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            // Primary CTA
            Button {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                onContinue()
            } label: {
                HStack(spacing: 8) {
                    Text("Let's Pick Shows")
                        .font(.custom("SF Pro Text", size: 16).weight(.bold))
                    Image(systemName: "arrow.right")
                        .scaledFont(size: 14, weight: .bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.orange.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color.orange.opacity(0.45), radius: 24, x: 0, y: 0)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            // Secondary skip
            Button(action: onSkip) {
                Text("Skip, take me home")
                    .font(.custom("SF Pro Text", size: 14).weight(.medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.navy)
    }

    // MARK: - Helpers

    static func serviceBadgeColor(_ name: String) -> Color {
        switch name {
        case "Netflix": return Color(red: 0.90, green: 0.03, blue: 0.08)
        case "Hulu": return Color(red: 0.11, green: 0.91, blue: 0.51)
        case "Paramount+": return Color(red: 0.00, green: 0.39, blue: 1.00)
        case "Max", "HBO Max": return Color(red: 0.34, green: 0.13, blue: 0.71)
        case "Disney+": return Color(red: 0.04, green: 0.24, blue: 0.57)
        case "Apple TV+": return Color.black
        case "Peacock": return Color(red: 0.96, green: 0.51, blue: 0.12)
        case "Prime Video": return Color(red: 0.00, green: 0.55, blue: 0.75)
        default: return Color.blue
        }
    }

    static func serviceBadgeAbbr(_ name: String) -> String {
        switch name {
        case "Netflix": return "N"
        case "Hulu": return "Hu"
        case "Paramount+": return "P+"
        case "Max", "HBO Max": return "MAX"
        case "Disney+": return "D+"
        case "Apple TV+": return "TV+"
        case "Peacock": return "Pc"
        case "Prime Video": return "PV"
        default: return String(name.prefix(2)).uppercased()
        }
    }

    private func infoRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Color.orange)
            Text(text)
                .font(.custom("SF Pro Text", size: 13))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    SeedPromptView(selectedServices: ["Netflix", "Max", "Paramount+"], onContinue: {}, onSkip: {})
        .preferredColorScheme(.dark)
}
