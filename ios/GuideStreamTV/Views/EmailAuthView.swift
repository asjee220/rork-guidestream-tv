//
//  EmailAuthView.swift
//  GuideStreamTV
//
//  Email + password authentication sheet. The very first time a user opens
//  this screen on a device it defaults to the "Create account" flow; every
//  subsequent visit defaults to "Sign in". Users can flip between modes at
//  any time, request a password-reset email, and see in-line validation and
//  Supabase error messages.
//
//  Supabase emails the recovery link with the `guidestream://auth-callback`
//  redirect, which the app handles via URL schemes so the user lands back
//  in the auth flow after tapping the link.
//

import SwiftUI
import UIKit

enum EmailAuthMode {
    case signUp
    case signIn
}

struct EmailAuthView: View {
    var onAuthenticated: () -> Void
    var onClose: () -> Void

    @State private var auth = AuthViewModel.shared
    @State private var mode: EmailAuthMode
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var showForgotPassword: Bool = false
    @State private var pendingConfirmation: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field { case firstName, lastName, email, password, confirm }

    init(onAuthenticated: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onAuthenticated = onAuthenticated
        self.onClose = onClose
        // First touch on this device → create account. After that → sign in.
        _mode = State(initialValue: AuthViewModel.shared.hasUsedEmailAuth ? .signIn : .signUp)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()

                // Atmosphere
                GeometryReader { geo in
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 90)
                        .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.35)
                    Circle()
                        .fill(Color.orange.opacity(0.10))
                        .frame(width: geo.size.width * 0.7)
                        .blur(radius: 80)
                        .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.45)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if pendingConfirmation {
                            confirmationBanner
                        }

                        fieldsCard

                        actionButton

                        forgotPasswordRow

                        modeToggle

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
                .presentationContentInteraction(.scrolls)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { close() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(prefilledEmail: email)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            BrandWordmark(wordmarkSize: .nav)
            .padding(.top, 8)

            Text(mode == .signUp ? "Create your account" : "Welcome back")
                .font(.custom("SF Pro Display", size: 28).weight(.bold))
                .foregroundStyle(.white)

            Text(mode == .signUp
                 ? "Use your email to save your services and pick up where you left off on any device."
                 : "Sign in with the email you used last time.")
                .font(.custom("SF Pro Text", size: 14))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confirmationBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "envelope.badge.fill")
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Check your inbox")
                    .font(.custom("SF Pro Text", size: 14).weight(.semibold))
                    .foregroundStyle(.white)
                Text("We just sent a confirmation link to \(email). Tap it, then come back here and sign in.")
                    .font(.custom("SF Pro Text", size: 12))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private var fieldsCard: some View {
        VStack(spacing: 0) {
            if mode == .signUp {
                field(
                    title: "First name",
                    text: $firstName,
                    placeholder: "Jane",
                    contentType: .givenName,
                    keyboard: .default,
                    isSecure: false,
                    isFocused: focusedField == .firstName,
                    fieldKey: .firstName,
                    autocapitalize: .words
                )
                Divider().background(Color.white.opacity(0.06))
                field(
                    title: "Last name",
                    text: $lastName,
                    placeholder: "Smith",
                    contentType: .familyName,
                    keyboard: .default,
                    isSecure: false,
                    isFocused: focusedField == .lastName,
                    fieldKey: .lastName,
                    autocapitalize: .words
                )
                Divider().background(Color.white.opacity(0.06))
            }

            field(
                title: "Email",
                text: $email,
                placeholder: "you@example.com",
                contentType: .emailAddress,
                keyboard: .emailAddress,
                isSecure: false,
                isFocused: focusedField == .email,
                fieldKey: .email
            )
            Divider().background(Color.white.opacity(0.06))

            field(
                title: "Password",
                text: $password,
                placeholder: mode == .signUp ? "At least 8 characters" : "Your password",
                contentType: mode == .signUp ? .newPassword : .password,
                keyboard: .default,
                isSecure: true,
                isFocused: focusedField == .password,
                fieldKey: .password
            )

            if mode == .signUp {
                Divider().background(Color.white.opacity(0.06))
                field(
                    title: "Confirm password",
                    text: $confirmPassword,
                    placeholder: "Re-enter your password",
                    contentType: .newPassword,
                    keyboard: .default,
                    isSecure: true,
                    isFocused: focusedField == .confirm,
                    fieldKey: .confirm
                )
            }
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
        keyboard: UIKeyboardType,
        isSecure: Bool,
        isFocused: Bool,
        fieldKey: Field,
        autocapitalize: TextInputAutocapitalization = .never
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("SF Pro Text", size: 11).weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .tracking(0.4)
            Group {
                if isSecure {
                    SecureField("", text: text, prompt: Text(placeholder)
                        .foregroundStyle(Color.white.opacity(0.25)))
                        .focused($focusedField, equals: fieldKey)
                } else {
                    TextField("", text: text, prompt: Text(placeholder)
                        .foregroundStyle(Color.white.opacity(0.25)))
                        .focused($focusedField, equals: fieldKey)
                        .textInputAutocapitalization(autocapitalize)
                        .keyboardType(keyboard)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(contentType)
            .foregroundStyle(.white)
            .tint(Color.orange)
            .font(.custom("SF Pro Text", size: 16))
            .submitLabel(submitLabel(for: fieldKey))
            .onSubmit { advanceFocus(from: fieldKey) }
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
                Text(submitLabel)
                    .font(.custom("SF Pro Text", size: 16).weight(.bold))
                Image(systemName: "arrow.right")
                    .scaledFont(size: 14, weight: .bold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [Color.orange, Color.orange.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )
                .opacity(canSubmit ? 1.0 : 0.4)
            )
            .clipShape(Capsule())
            .shadow(color: Color.orange.opacity(canSubmit ? 0.45 : 0), radius: 22, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || auth.isAuthenticating)
    }

    @ViewBuilder
    private var forgotPasswordRow: some View {
        if mode == .signIn {
            HStack {
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showForgotPassword = true
                } label: {
                    Text("Forgot password?")
                        .font(.custom("SF Pro Text", size: 13).weight(.medium))
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            Text(mode == .signUp ? "Already have an account?" : "New here?")
                .font(.custom("SF Pro Text", size: 13))
                .foregroundStyle(Color.textSecondary)
            Button {
                // Clear stale messages when the user manually flips modes.
                auth.lastError = nil
                auth.lastInfo = nil
                pendingConfirmation = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    mode = (mode == .signUp) ? .signIn : .signUp
                }
            } label: {
                Text(mode == .signUp ? "Sign in" : "Create account")
                    .font(.custom("SF Pro Text", size: 13).weight(.semibold))
                    .foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 4)
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

    // MARK: - Derived

    private var submitLabel: String {
        mode == .signUp ? "Create account" : "Sign in"
    }

    private var canSubmit: Bool {
        guard isEmailLikelyValid else { return false }
        guard password.count >= 8 else { return false }
        if mode == .signUp {
            guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty,
                  !lastName.trimmingCharacters(in: .whitespaces).isEmpty else {
                return false
            }
            return password == confirmPassword
        }
        return true
    }

    private var isEmailLikelyValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    // MARK: - Actions

    private func submit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        focusedField = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = password
        Task {
            let ok: Bool
            switch mode {
            case .signUp:
                ok = await auth.signUpWithEmail(
                    email: trimmedEmail,
                    password: pass,
                    firstName: trimmedFirst,
                    lastName: trimmedLast
                )
                if !ok {
                    // Either email confirmation is pending, or a "user already
                    // exists" sign-in fallback succeeded inside the helper.
                    if auth.isAuthenticated {
                        onAuthenticated()
                    } else if auth.lastInfo != nil {
                        pendingConfirmation = true
                        // Move user to sign-in mode so they can complete after
                        // tapping the confirmation link.
                        mode = .signIn
                    }
                    return
                }
            case .signIn:
                ok = await auth.signInWithEmail(email: trimmedEmail, password: pass)
            }
            if ok { onAuthenticated() }
        }
    }

    private func submitLabel(for field: Field) -> SubmitLabel {
        switch field {
        case .firstName, .lastName, .email: return .next
        case .password: return mode == .signUp ? .next : .go
        case .confirm: return .go
        }
    }

    private func advanceFocus(from field: Field) {
        switch field {
        case .firstName:
            focusedField = .lastName
        case .lastName:
            focusedField = .email
        case .email:
            focusedField = .password
        case .password:
            if mode == .signUp {
                focusedField = .confirm
            } else if canSubmit {
                submit()
            }
        case .confirm:
            if canSubmit { submit() }
        }
    }

    private func close() {
        auth.lastError = nil
        auth.lastInfo = nil
        onClose()
    }
}

// MARK: - Forgot password sheet

struct ForgotPasswordSheet: View {
    var prefilledEmail: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthViewModel.shared
    @State private var email: String = ""
    @State private var sent: Bool = false
    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()

                GeometryReader { geo in
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: geo.size.width * 0.8)
                        .blur(radius: 90)
                        .offset(x: geo.size.width * 0.3, y: -geo.size.height * 0.3)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 76, height: 76)
                            Image(systemName: sent ? "envelope.badge.fill" : "envelope.fill")
                                .scaledFont(size: 28, weight: .semibold)
                                .foregroundStyle(Color.orange)
                        }
                        .padding(.top, 8)

                        Text(sent ? "Check your inbox" : "Reset your password")
                            .font(.custom("SF Pro Display", size: 26).weight(.bold))
                            .foregroundStyle(.white)

                        Text(sent
                             ? "If \(email) is registered, you'll get a recovery link in a minute. Open it on this device to set a new password."
                             : "Enter the email tied to your account and we'll send a one-time recovery link.")
                            .font(.custom("SF Pro Text", size: 14))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !sent {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Email")
                                    .font(.custom("SF Pro Text", size: 11).weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                                    .tracking(0.4)
                                TextField("", text: $email, prompt: Text("you@example.com")
                                    .foregroundStyle(Color.white.opacity(0.25)))
                                    .focused($emailFocused)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .submitLabel(.send)
                                    .onSubmit(send)
                                    .foregroundStyle(.white)
                                    .tint(Color.orange)
                                    .font(.custom("SF Pro Text", size: 16))
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )

                            Button(action: send) {
                                HStack(spacing: 8) {
                                    if auth.isAuthenticating {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .tint(.white)
                                    }
                                    Text("Send recovery email")
                                        .font(.custom("SF Pro Text", size: 16).weight(.bold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    LinearGradient(
                                        colors: [Color.orange, Color.orange.opacity(0.85)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                    .opacity(canSend ? 1 : 0.4)
                                )
                                .clipShape(Capsule())
                                .shadow(color: Color.orange.opacity(canSend ? 0.4 : 0),
                                        radius: 18, x: 0, y: 0)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSend || auth.isAuthenticating)
                        } else {
                            Button {
                                dismiss()
                            } label: {
                                Text("Back to sign in")
                                    .font(.custom("SF Pro Text", size: 16).weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(
                                        Capsule().fill(Color.white.opacity(0.08))
                                    )
                                    .overlay(
                                        Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        if let err = auth.lastError, !err.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .scaledFont(size: 13, weight: .semibold)
                                    .foregroundStyle(Color.red.opacity(0.85))
                                Text(err)
                                    .font(.custom("SF Pro Text", size: 12))
                                    .foregroundStyle(Color.red.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .presentationContentInteraction(.scrolls)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            email = prefilledEmail
            auth.lastError = nil
            auth.lastInfo = nil
            // Delay the focus a beat so the sheet animates in cleanly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if !sent && email.isEmpty {
                    emailFocused = true
                }
            }
        }
    }

    private var canSend: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    private func send() {
        guard canSend else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        emailFocused = false
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        Task {
            let ok = await auth.sendPasswordReset(email: trimmed)
            if ok { sent = true }
        }
    }
}

#Preview("Email Auth") {
    EmailAuthView(onAuthenticated: {}, onClose: {})
}

#Preview("Forgot Password") {
    ForgotPasswordSheet(prefilledEmail: "user@example.com")
}
