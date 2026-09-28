//
//  MacSignInView.swift
//  GuideStreamTVMac
//
//  First launch: Sign in with Apple, email, or browse as a guest. New
//  accounts are created with Apple here or in the phone app.
//

import SwiftUI
import AuthenticationServices

struct MacSignInView: View {
    @State private var auth = MacAuthViewModel.shared
    @State private var email = ""
    @State private var password = ""
    @State private var showEmail = false

    var body: some View {
        VStack(spacing: 28) {
            Image("AppMark")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: MacColor.orange.opacity(0.35), radius: 30)
            VStack(spacing: 8) {
                MacWordmark(size: 34)
                Text("Everything you watch. Everyone you follow. In one place.")
                    .font(.system(size: 15))
                    .foregroundStyle(MacColor.text2)
            }

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    AuthViewModel.shared.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task { await AuthViewModel.shared.handleAppleCompletion(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(width: 300, height: 44)

                if showEmail {
                    VStack(spacing: 10) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .onSubmit(signInEmail)
                        Button(action: signInEmail) {
                            Text(auth.isAuthenticating ? "Signing in…" : "Sign in")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(MacColor.orange, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(email.isEmpty || password.isEmpty || auth.isAuthenticating)
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                } else {
                    Button("Sign in with email") { showEmail = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MacColor.orange)
                }

                if let error = auth.lastError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                        .multilineTextAlignment(.center)
                        .frame(width: 320)
                }
            }

            Button("Browse as guest") { auth.continueAsGuest() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(MacColor.text2)
        }
        .padding(40)
    }

    private func signInEmail() {
        Task { await AuthViewModel.shared.signInWithEmail(email: email, password: password) }
    }
}

/// "GuideStream TV" wordmark: white Guide, orange Stream, blue TV.
struct MacWordmark: View {
    var size: CGFloat = 19
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Guide").foregroundStyle(.white)
            Text("Stream").foregroundStyle(MacColor.orange)
            Text("TV")
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(MacColor.blue)
                .baselineOffset(size * 0.45)
                .padding(.leading, 2)
        }
        .font(.system(size: size, weight: .bold))
        .lineLimit(1)
        .fixedSize()
    }
}
