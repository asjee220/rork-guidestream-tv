//
//  TVSupportFormView.swift
//  GuideStreamTVTV
//
//  GUI-87 — Contact Support and Report a Problem on tvOS.
//

import SwiftUI
import UIKit

/// In-app support form for Apple TV, presented as a full-screen cover from
/// Help & Feedback.
///
/// tvOS has no Mail app and no web container, so the previous `mailto:` rows
/// were silently dead. A native form is the only thing that can work here.
/// It is deliberately short — a topic the viewer picks with the remote, an
/// email address that prefills from the signed-in account, and one message
/// field — because every character costs a trip round the on-screen keyboard.
/// The version, build, hardware model, tvOS version and device id ride along
/// automatically.
struct TVSupportFormView: View {
    let presetTopic: String

    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthViewModel.shared

    @State private var topic: String
    @State private var email: String = ""
    @State private var message: String = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var sent = false

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
        ZStack {
            Color.navy.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    if sent {
                        sentCard
                    } else {
                        Text("Contact Support")
                            .scaledFont(size: 34, weight: .bold)
                            .foregroundStyle(.white)
                        Text("Tell us what's going on and we'll reply by email.")
                            .scaledFont(size: 16)
                            .foregroundStyle(Color.textSecondary)

                        sectionLabel("TOPIC")
                        ProfileCard {
                            ForEach(Array(TVSupportRequestService.topics.enumerated()), id: \.element) { idx, option in
                                if idx > 0 { ProfileRowDivider() }
                                Button { topic = option } label: {
                                    HStack {
                                        Text(option)
                                            .scaledFont(size: 20)
                                            .foregroundStyle(.white)
                                        Spacer()
                                        if option == topic {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Color.orange)
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 16)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.card)
                            }
                        }

                        sectionLabel("YOUR EMAIL")
                        TextField("you@example.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        sectionLabel("MESSAGE")
                        TextField("What happened?", text: $message)
                            .onChange(of: message) { _, newValue in
                                if newValue.count > 4000 { message = String(newValue.prefix(4000)) }
                            }

                        Text("We'll include your app version (\(TVSupportRequestService.appVersion)), device and device ID so we can find the problem faster.")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.textTertiary)

                        if let errorText {
                            Text(errorText)
                                .scaledFont(size: 15)
                                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                        }

                        HStack(spacing: 16) {
                            Button(isSending ? "Sending…" : "Send", action: send)
                                .disabled(!canSend)
                            Button("Cancel") { dismiss() }
                        }
                        .padding(.top, 6)
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.horizontal, 60)
                .padding(.vertical, 50)
            }
        }
    }

    private var sentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Message sent")
                .scaledFont(size: 34, weight: .bold)
                .foregroundStyle(.white)
            Text("Thanks — we've got it. We'll reply to \(email.trimmingCharacters(in: .whitespaces)).")
                .scaledFont(size: 18)
                .foregroundStyle(Color.textSecondary)
            Button("Done") { dismiss() }
                .padding(.top, 10)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 13, weight: .semibold)
            .tracking(0.8)
            .foregroundStyle(Color.textTertiary)
            .padding(.top, 6)
    }

    private func send() {
        guard canSend else { return }
        isSending = true
        errorText = nil
        Task {
            let ok = await TVSupportRequestService.submit(
                name: auth.displayName ?? "",
                email: email.trimmingCharacters(in: .whitespaces),
                topic: topic,
                message: message.trimmingCharacters(in: .whitespaces)
            )
            await MainActor.run {
                isSending = false
                if ok { sent = true } else {
                    errorText = "Couldn't send that. Check your connection and try again."
                }
            }
        }
    }
}

/// A preselected topic wrapped for `.fullScreenCover(item:)`.
struct TVSupportTopicRequest: Identifiable {
    let id = UUID()
    let topic: String
}

/// A legal page wrapped for `.fullScreenCover(item:)`.
struct TVLegalNotice: Identifiable {
    let id = UUID()
    let title: String
    let url: String
}

/// Shown when a viewer selects Privacy Policy or Terms of Service on Apple TV.
///
/// tvOS ships no web container at all, so those rows previously called
/// `UIApplication.open` on an https URL and did nothing. Rather than leave a
/// dead button, we tell the viewer where to read the page on a device that
/// has a browser.
struct TVLegalNoticeView: View {
    let title: String
    let url: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.navy.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .scaledFont(size: 34, weight: .bold)
                    .foregroundStyle(.white)
                Text("Apple TV has no web browser, so this page can't open here. Read it on your phone or computer at:")
                    .scaledFont(size: 18)
                    .foregroundStyle(Color.textSecondary)
                Text(url)
                    .scaledFont(size: 24, weight: .semibold)
                    .foregroundStyle(Color.orange)
                Button("Done") { dismiss() }
                    .padding(.top, 12)
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(60)
        }
    }
}
