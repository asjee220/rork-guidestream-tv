//
//  PlaceholderViews.swift
//  GuideStreamTV
//

import SwiftUI
import Auth

struct LiveTVView: View {
    var body: some View {
        PlaceholderShell(
            symbol: "dot.radiowaves.left.and.right",
            title: "Live TV",
            subtitle: "Live channels from every provider, one guide.",
            accent: Theme.blue
        )
    }
}

struct ProfileView: View {
    @State private var auth = AuthViewModel.shared

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Theme.blue.opacity(0.18))
                        .frame(width: 130, height: 130)
                        .blur(radius: 22)
                    Circle()
                        .stroke(Theme.blue.opacity(0.4), lineWidth: 1)
                        .frame(width: 100, height: 100)
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Theme.blue)
                }

                Text(displayName)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(.white)

                if let email = auth.currentUser?.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer().frame(height: 8)

                Button {
                    Task { await auth.signOut() }
                } label: {
                    Text("Sign Out")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 280)
                        .frame(height: 52)
                        .background(Color.orange)
                        .clipShape(Capsule())
                        .shadow(color: Color.orange.opacity(0.35), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var displayName: String {
        return "Your Profile"
    }
}

struct AskStreamView: View {
    var body: some View {
        PlaceholderShell(
            symbol: "sparkles",
            title: "Ask Stream",
            subtitle: "Your AI co-pilot for what to watch tonight.",
            accent: Theme.orange
        )
    }
}

struct PlaceholderShell: View {
    let symbol: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 130, height: 130)
                    .blur(radius: 22)
                Circle()
                    .stroke(accent.opacity(0.4), lineWidth: 1)
                    .frame(width: 100, height: 100)
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(accent)
            }
            Text(title)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
