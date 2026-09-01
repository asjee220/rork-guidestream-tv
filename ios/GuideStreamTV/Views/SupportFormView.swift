//
//  SupportFormView.swift
//  GuideStreamTV
//
//  GUI-87 — Contact Support and Report a Problem without leaving the app.
//

import SwiftUI
import UIKit
import Supabase

/// In-app support form, presented as a sheet from Help & Feedback.
///
/// Replaces the two `mailto:` hand-offs. The app version, build, device model,
/// OS version and device id are attached by `SupportRequestService` rather
/// than pasted into an email body people routinely deleted, and the request
/// lands in `support_requests` with `channel = "app"` so the existing triage
/// picks it up unchanged.
struct SupportFormView: View {
    /// Topic the row that opened the sheet preselects.
    let presetTopic: String

    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthViewModel.shared

    @State private var topic: String
    @State private var email: String = ""
    @State private var message: String = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var sent = false
    @FocusState private var messageFocused: Bool

    init(presetTopic: String) {
        self.presetTopic = presetTopic
        _topic = State(initialValue: presetTopic)
    }

    private var emailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    private var canSend: Bool {
        !isSending && emailValid && !message.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()

                ScrollView(showsIndicators: false) {
                    if sent {
                        sentCard
                    } else {
                        VStack(spacing: 18) {
                            topicCard
                            emailCard
                            messageCard
                            footerNote
                            sendButton
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 60)
                    }
                }
            }
            .navigationTitle(sent ? "Message sent" : "Contact Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.navy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .onAppear {
            if email.isEmpty { email = auth.currentUser?.email ?? "" }
        }
    }

    // MARK: - Sections

    private var topicCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TOPIC")
            ProfileCard {
                ForEach(Array(SupportRequestService.topics.enumerated()), id: \.element) { idx, option in
                    if idx > 0 { ProfileRowDivider() }
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        topic = option
                    } label: {
                        HStack {
                            Text(option)
                                .scaledFont(size: 15)
                                .foregroundStyle(.white)
                            Spacer()
                            if option == topic {
                                Image(systemName: "checkmark")
                                    .scaledFont(size: 13, weight: .bold)
                                    .foregroundStyle(Color.orange)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("YOUR EMAIL")
            TextField("you@example.com", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .scaledFont(size: 16)
                .foregroundStyle(.white)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("MESSAGE")
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text("What happened, and what were you doing at the time?")
                        .scaledFont(size: 15)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $message)
                    .focused($messageFocused)
                    .scaledFont(size: 15)
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .onChange(of: message) { _, newValue in
                        if newValue.count > 4000 { message = String(newValue.prefix(4000)) }
                    }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("We'll include your app version (\(SupportRequestService.appVersion)), device and device ID so we can find the problem faster.")
                .scaledFont(size: 11)
                .foregroundStyle(Color.textTertiary)
            if let errorText {
                Text(errorText)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sendButton: some View {
        Button(action: send) {
            HStack(spacing: 8) {
                if isSending { ProgressView().tint(.white) }
                Text(isSending ? "Sending…" : "Send")
                    .scaledFont(size: 15, weight: .bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(canSend ? Color.orange : Color.orange.opacity(0.35))
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    private var sentCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .scaledFont(size: 48)
                .foregroundStyle(Color.orange)
            Text("Thanks — we've got it.")
                .scaledFont(size: 17, weight: .semibold)
                .foregroundStyle(.white)
            Text("We'll reply to \(email.trimmingCharacters(in: .whitespaces)).")
                .scaledFont(size: 13)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 30)
        .padding(.top, 60)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 11, weight: .semibold)
            .tracking(0.8)
            .foregroundStyle(Color.textTertiary)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func send() {
        guard canSend else { return }
        isSending = true
        errorText = nil
        messageFocused = false
        Task {
            let ok = await SupportRequestService.submit(
                name: auth.displayName ?? "",
                email: email.trimmingCharacters(in: .whitespaces),
                topic: topic,
                message: message.trimmingCharacters(in: .whitespaces)
            )
            await MainActor.run {
                isSending = false
                if ok {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    sent = true
                } else {
                    errorText = "Couldn't send that. Check your connection and try again."
                }
            }
        }
    }
}

/// A preselected topic wrapped for `.sheet(item:)`.
struct SupportTopicRequest: Identifiable {
    let id = UUID()
    let topic: String
}
