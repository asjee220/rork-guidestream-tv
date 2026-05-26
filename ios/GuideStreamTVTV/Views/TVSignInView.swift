//
//  TVSignInView.swift
//  GuideStreamTVTV
//
//  Sign-in landing screen. Mirrors the phone app's auth gate:
//   * "Sign in with Apple" — same Supabase auth, same identity
//   * "Continue as Guest" — backs the watch list with a device id
//

import SwiftUI
import AuthenticationServices

struct TVSignInView: View {
    @State private var auth = TVAuthViewModel.shared
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            TVTheme.backgroundGradient

            // Brand glow accents
            GeometryReader { proxy in
                Circle()
                    .fill(TVTheme.orange.opacity(0.25))
                    .frame(width: 800, height: 800)
                    .blur(radius: 220)
                    .offset(x: -200, y: -200)
                Circle()
                    .fill(TVTheme.blue.opacity(0.20))
                    .frame(width: 900, height: 900)
                    .blur(radius: 260)
                    .offset(x: proxy.size.width - 600, y: proxy.size.height - 600)
            }
            .ignoresSafeArea()

            HStack(spacing: 80) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 14) {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 44, weight: .black))
                            .foregroundStyle(TVTheme.orange)
                        Text("GuideStream")
                            .font(.system(size: 38, weight: .black))
                            .foregroundStyle(.white)
                    }
                    Text("Your living-room\nentertainment guide.")
                        .font(.system(size: 64, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                    Text("Sign in to sync your watch list with your phone, or start browsing right away.")
                        .font(.system(size: 24))
                        .foregroundStyle(TVTheme.textSecondary)
                        .frame(maxWidth: 620, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 24) {
                    SignInWithAppleButton(
                        .signIn,
                        onRequest: { request in
                            auth.prepareAppleRequest(request)
                        },
                        onCompletion: { result in
                            Task {
                                await auth.handleAppleCompletion(result)
                                if auth.isAuthenticated { onContinue() }
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.white)
                    .frame(width: 480, height: 92)
                    .cornerRadius(20)

                    Button {
                        auth.continueAsGuest()
                        onContinue()
                    } label: {
                        Text("Continue as Guest")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 480, height: 80)
                    }
                    .buttonStyle(.card)

                    if let err = auth.lastError {
                        Text(err)
                            .font(.system(size: 16))
                            .foregroundStyle(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480)
                            .padding(.top, 8)
                    }

                    Text("Already signed in on your phone?\nUse the same Apple ID here to sync instantly.")
                        .font(.system(size: 16))
                        .foregroundStyle(TVTheme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 100)
        }
    }
}
