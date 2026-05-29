//
//  SeedPromptView.swift
//  GuideStreamTV
//

import SwiftUI
import UIKit

/// Onboarding step 3 — introduces the "Seed Your List" concept and invites
/// the user to pick shows they follow so their Watch List is pre-populated.
struct SeedPromptView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(progress: 0.75)

            Spacer(minLength: 20)

            // Service badge row
            HStack(spacing: 12) {
                serviceBadge(text: "N", bg: Color(hex: "E50914"), fontSize: 16, weight: .bold)
                serviceBadge(text: "MAX", bg: Color(hex: "5822B4"), fontSize: 9, weight: .bold)
                serviceBadge(text: "P+", bg: Color(hex: "0064FF"), fontSize: 11, weight: .bold)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(hex: "F5821F"), lineWidth: 2)
                    )
            }

            Spacer(minLength: 16)

            // "NEW STEP" pill
            Text("NEW STEP")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .tracking(0.06)
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.orange.opacity(0.10)))
                .overlay(Capsule().stroke(Color.orange.opacity(0.35), lineWidth: 1))

            Spacer(minLength: 14)

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

    private func serviceBadge(text: String, bg: Color, fontSize: CGFloat, weight: Font.Weight) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(bg)
            .frame(width: 48, height: 48)
            .overlay(
                Text(text)
                    .font(.system(size: fontSize, weight: weight, design: .default))
                    .foregroundStyle(.white)
            )
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
    SeedPromptView(onContinue: {}, onSkip: {})
        .preferredColorScheme(.dark)
}
