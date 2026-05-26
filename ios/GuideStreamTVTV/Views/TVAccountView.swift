//
//  TVAccountView.swift
//  GuideStreamTVTV
//
//  Account tab: avatar pill, current sign-in state, and a sign-out
//  button. Intentionally minimal — phone app handles the heavy
//  account/preferences flows.
//

import SwiftUI

struct TVAccountView: View {
    @State private var auth = TVAuthViewModel.shared
    let onSignOut: () -> Void

    private var status: String {
        if auth.isAuthenticated {
            return "Signed in"
        } else if auth.isGuest {
            return "Browsing as guest"
        }
        return "Signed out"
    }

    private var subtitle: String {
        if auth.isAuthenticated {
            return auth.currentUser?.email ?? "Apple account"
        } else if auth.isGuest {
            return "Your watch list is saved to this Apple TV"
        }
        return ""
    }

    var body: some View {
        ZStack {
            TVTheme.backgroundGradient

            VStack(spacing: 36) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [TVTheme.orange, TVTheme.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 200)
                    .overlay {
                        Text(auth.initials)
                            .font(.system(size: 86, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: TVTheme.orange.opacity(0.4), radius: 30)

                VStack(spacing: 10) {
                    Text(auth.displayName ?? (auth.isGuest ? "Guest" : "GuideStream"))
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(.white)
                    Text(status)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(TVTheme.orange)
                        .tracking(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 20))
                            .foregroundStyle(TVTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Button {
                    Task {
                        await auth.signOut()
                        onSignOut()
                    }
                } label: {
                    Text("Sign Out")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 18)
                }
                .buttonStyle(.card)
                .padding(.top, 8)

                Text("Want to manage your services and preferences? Open GuideStream on your phone.")
                    .font(.system(size: 18))
                    .foregroundStyle(TVTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)
                    .padding(.top, 24)
            }
        }
    }
}
