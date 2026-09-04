//
//  AppleTVSignInHelpSheet.swift
//  GuideStreamTV
//
//  The long version of why an Apple TV is, or isn't, in the Play on TV list.
//
//  The short version lives in the cast sheet's header. This is what the
//  "Why isn't my Apple TV here?" link opens: plain language, no topics, no
//  accounts-and-realtime-channels, because the person reading it wants their
//  show on the big screen, not an architecture lesson.
//
//  Modelled on `LimitedModeHelpSheet` so the two help surfaces match.
//

import SwiftUI

struct AppleTVSignInHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                explanation
                stepsCard
                whyCard
                notListedCard
                doneButton
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .presentationDetents([.large])
        .presentationSizing(.page)
        .sheetSurface(.raised)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "appletv.fill")
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundStyle(Color.orange)
                    .padding(8)
                    .background(Circle().fill(Color.orange.opacity(0.18)))
                Text("Why isn't my Apple TV here?")
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Because Apple TV only takes a show from your phone when GuideStream is running on the TV and signed in to the same account you use here.")
                .scaledFont(size: 14)
                .foregroundStyle(Color.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var explanation: some View {
        Text("Sign in on the TV once and it stays signed in. Here's how.")
            .scaledFont(size: 13, weight: .semibold)
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepRow(
                number: 1,
                title: "Open GuideStream on your Apple TV",
                detail: "If it isn't installed, get it from the App Store on the Apple TV first."
            )
            divider
            stepRow(
                number: 2,
                title: "Open the menu and choose Profile",
                detail: "Swipe left on the remote to open the menu down the side, then pick Profile."
            )
            divider
            stepRow(
                number: 3,
                title: "Scroll to the bottom and choose Sign In",
                detail: "Use the same account you're signed in with on this phone — same email, signed in the same way. A different account won't be paired to it."
            )
            divider
            stepRow(
                number: 4,
                title: "Come back to Play on TV",
                detail: "Your Apple TV appears in the list, by the name it has in the TV's own settings — \"Living Room\", say."
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }

    private var whyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .scaledFont(size: 14)
                .foregroundStyle(Color.blue)
            Text("Apple doesn't let a phone reach into an Apple TV and open somebody else's app. So GuideStream on the TV does the opening itself — your phone just passes it a message. Signing in on the TV is what connects the two, and it's why the sign-in has to be the same account on both.")
                .scaledFont(size: 12)
                .foregroundStyle(Color.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        )
    }

    private var notListedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Signed in and still not showing?")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(.white)
            bullet("Make sure the phone and the Apple TV are on the same Wi-Fi.")
            bullet("Check you're signed in here too — a signed-out phone can't pair with any TV.")
            bullet("If the TV shows \"Exit Guest Mode\" instead of \"Sign In\", choose that first, then sign in.")
            bullet("Open GuideStream on the TV again, then tap Rescan here.")
            bullet("Other AirPlay devices — smart TVs, iPads, speakers — can't run GuideStream, so they never appear in this list.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .scaledFont(size: 12, weight: .bold)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(text)
                .scaledFont(size: 12)
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var doneButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } label: {
            Text("Got it")
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                )
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 0.5)
    }

    private func stepRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .scaledFont(size: 13, weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.orange.opacity(0.85)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
