//
//  UpdatePasswordView.swift
//  GuideStreamTV
//
//  Set-new-password screen presented when a Supabase recovery callback
//  imports a session. Shown as a fullScreenCover from ContentView when
//  `AuthViewModel.showPasswordRecovery` is true. Reuses the exact field
//  styling, orange-gradient action button, and typography from
//  `EmailAuthView.swift` so the experience is consistent with the rest of
//  the email auth flow.
//

import SwiftUI
import UIKit

struct UpdatePasswordView: View {
    /// Called when the password has been updated and the user should land
    /// in the signed-in app. Defaults to clearing the recovery flag.
    var onDismiss: () -> Void

    @State private var auth = AuthViewModel.shared
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @FocusState private var focusedField: Field?

    private enum Field { case newPassword, confirm }

    private var canSubmit: Bool {
        newPassword.count >= 8 && newPassword == confirmPassword
    }

    var body: some View {
        ZStack {
            BrandBackground()

            // Atmosphere — matches EmailAuthView's glows.
            GeometryReader { geo in
                Circle()
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: geo.size.width * 0.9)
                    .blur(radius: 90)
                    .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.35)
                Circle()
                    .fill(Color.blue.opacity(0.10))
                    .frame(width: geo.size.width * 0.7)
                    .blur(radius: 80)
                    .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.45)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    fieldsCard

                    actionButton

                    if let err = auth.lastError, !err.isEmpty {
                        statusMessage(err, isError: true)
                    }
                    if let info = auth.lastInfo, !info.isEmpty {
                        statusMessage(info, isError: false)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Clear stale messages from a prior auth flow so the recovery
            // screen starts clean.
            auth.lastError = nil
            auth.lastInfo = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                focusedField = .newPassword
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "lock.rotation")
                    .scaledFont(size: 26, weight: .semibold)
                    .foregroundStyle(Color.orange)
            }
            .padding(.top, 8)

            Text("Set a new password")
                .font(.custom("SF Pro Display", size: 28).weight(.bold))
                .foregroundStyle(.white)

            Text("Choose a new password for your account. You'll be signed in automatically once it's updated.")
                .font(.custom("SF Pro Text", size: 14))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fieldsCard: some View {
        VStack(spacing: 0) {
            field(
                title: "New password",
                text: $newPassword,
                placeholder: "At least 8 characters",
                contentType: .newPassword,
                isFocused: focusedField == .newPassword,
                fieldKey: .newPassword
            )
            Divider().background(Color.white.opacity(0.06))
            field(
                title: "Confirm password",
                text: $confirmPassword,
                placeholder: "Re-enter your new password",
                contentType: .newPassword,
                isFocused: focusedField == .confirm,
                fieldKey: .confirm
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func field(
        title: String,
        text: Binding<String>,
        placeholder: String,
        contentType: UITextContentType?,
        isFocused: Bool,
        fieldKey: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("SF Pro Text", size: 11).weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .tracking(0.4)
            SecureField("", text: text, prompt: Text(placeholder)
                .foregroundStyle(Color.white.opacity(0.25)))
                .focused($focusedField, equals: fieldKey)
                .textContentType(contentType)
                .foregroundStyle(.white)
                .tint(Color.orange)
                .font(.custom("SF Pro Text", size: 16))
                .submitLabel(fieldKey == .newPassword ? .next : .go)
                .onSubmit {
                    if fieldKey == .newPassword {
                        focusedField = .confirm
                    } else if canSubmit {
                        submit()
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var actionButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if auth.isAuthenticating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text("Update password")
                    .font(.custom("SF Pro Text", size: 16).weight(.bold))
                Image(systemName: "arrow.right")
                    .scaledFont(size: 14, weight: .bold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [Color.orange.opacity(canSubmit ? 1.0 : 0.4), Color.orange.opacity((canSubmit ? 1.0 : 0.4) * 0.85)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(Capsule())
            .shadow(color: Color.orange.opacity(canSubmit ? 0.45 : 0), radius: 22, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || auth.isAuthenticating)
    }

    private func statusMessage(_ text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(isError ? Color.red.opacity(0.85) : Color.green.opacity(0.85))
            Text(text)
                .font(.custom("SF Pro Text", size: 12))
                .foregroundStyle(isError ? Color.red.opacity(0.85) : Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    // MARK: - Actions

    private func submit() {
        guard canSubmit else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        focusedField = nil
        let pw = newPassword
        Task {
            let ok = await auth.updatePassword(newPassword: pw)
            if ok {
                // Drop the recovery screen and land the user in the signed-in
                // app. `onDismiss` clears `showPasswordRecovery`.
                await MainActor.run { onDismiss() }
            }
            // On failure, leave the user on the screen with the error visible
            // and the entered password preserved so they can retry.
        }
    }
}

#Preview {
    UpdatePasswordView(onDismiss: {})
}
