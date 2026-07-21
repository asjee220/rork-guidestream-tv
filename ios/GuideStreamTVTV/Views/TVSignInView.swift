//
//  TVSignInView.swift
//  GuideStreamTVTV
//
//  Sign-in landing screen. Mirrors the phone app's auth gate:
//   * "Sign in with Apple" — same Supabase auth, same identity
//   * "Continue as Guest" — backs the watch list with a device id
//      (now a smaller text link with a confirmation sheet)
//
//  After successful Apple sign-in the user is asked to name the room
//  this Apple TV is in (defaults to "Living Room") so the Play on TV
//  feature can target it from the phone app.
//

import SwiftUI
import AuthenticationServices

struct TVSignInView: View {
    @State private var auth = TVAuthViewModel.shared
    @FocusState private var isSignInFocused: Bool
    let onContinue: () -> Void

    // MARK: - Guest confirmation
    @State private var showGuestConfirm = false

    // MARK: - Room prompt (after Apple sign-in)
    @State private var showRoomPrompt = false
    @State private var roomName = "Living Room"
    @State private var roomIsSaving = false

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
                    TVBrandWordmark(wordmarkSize: .large)
                        .shadow(color: TVTheme.orange.opacity(0.4), radius: 30)
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.0),
                            Color.blue,
                            Color.orange,
                            Color.orange.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 4)
                    .frame(maxWidth: 560, alignment: .leading)
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
                    // Native SwiftUI Button instead of SignInWithAppleButton.
                    // SignInWithAppleButton wraps a UIKit ASAuthorizationAppleIDButton
                    // which doesn't work with tvOS focus — the UIViewRepresentable
                    // handles its own focus internally. A regular Button + ASAuthorizationController
                    // gives us full control over the tvOS focus ring.
                    Button {
                        auth.performAppleSignIn(onComplete: {
                            // Auth succeeded — prompt for room name before
                            // proceeding to the main app.
                            showRoomPrompt = true
                        })
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 28, weight: .semibold))
                            Text("Sign in with Apple")
                                .font(.system(size: 24, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(width: 480, height: 92)
                        .background(Color.white, in: .rect(cornerRadius: 20))
                    }
                    .buttonStyle(.card)
                    .focused($isSignInFocused)
                    .defaultFocus($isSignInFocused, true)
                    .disabled(auth.isAuthenticating || roomIsSaving)

                    // De-emphasised guest link — smaller, no card styling.
                    Button {
                        showGuestConfirm = true
                    } label: {
                        Text("Continue as Guest")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(TVTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(auth.isAuthenticating || roomIsSaving)

                    if let err = auth.lastError {
                        Text(err)
                            .font(.system(size: 16))
                            .foregroundStyle(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480)
                            .padding(.top, 8)
                    }

                    Text("Tap Sign in with Apple to enable Play on TV and sync your watch list.")
                        .font(.system(size: 16))
                        .foregroundStyle(TVTheme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(.horizontal, 100)
        }
        // MARK: - Guest confirmation sheet
        .alert(
            "Continue as Guest?",
            isPresented: $showGuestConfirm
        ) {
            Button("Sign in with Apple", role: .none) {
                // Dismiss and focus the Apple button — user explicitly
                // decided not to go the guest route.
            }
            Button("Continue as Guest", role: .none) {
                auth.continueAsGuest()
                onContinue()
            }
        } message: {
            Text("Play on TV and watch-list sync need sign-in. Continue as guest for browsing only?")
        }
        // MARK: - Room name prompt (after Apple sign-in)
        .alert("What room is this Apple TV in?", isPresented: $showRoomPrompt) {
            TextField("Living Room", text: $roomName)
            Button("Continue") {
                let room = roomName.trimmingCharacters(in: .whitespaces)
                roomIsSaving = true
                Task {
                    await auth.registerDevice(room: room.isEmpty ? "Living Room" : room)
                    await MainActor.run {
                        roomIsSaving = false
                        onContinue()
                    }
                }
            }
        } message: {
            Text("Name this Apple TV so your phone can find it for Play on TV.")
        }
    }
}
