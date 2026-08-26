//
//  PushReauthBanner.swift
//  GuideStreamTV
//
//  Home-screen prompt for the one state where notifications are off through
//  no decision of the user's: the account still wants push
//  (`users.notify_push = true`, restored from the server) but iOS reports
//  `.notDetermined`. Deleting an app revokes its notification authorization,
//  and a device the account has never run on never had one — so the copy says
//  "off on this device" rather than blaming a delete, which would be wrong in
//  the second case.
//
//  GUI-41 originally put this message on Profile → Notifications. That screen
//  is only ever reached deliberately, and someone who just reinstalled has no
//  reason to go looking — they would simply stop receiving alerts and never
//  find out why. Home is where they already are, so the prompt belongs here.
//  The settings banner stays as the explanation for anyone who does go looking.
//
//  Deliberately narrow. It does not appear on a new install (intent is false
//  until the server says otherwise, and onboarding does the first ask), and it
//  does not appear when the user turned notifications off in iOS Settings
//  themselves — that is `.denied`, a decision worth respecting, and iOS will
//  not re-prompt for it anyway.
//
//  Split into state + view so Home can write `if prompt.isVisible { … }`. A
//  self-contained view that returns an empty body still counts as a child of
//  Home's `VStack(spacing: 20)` and would leave a 20pt gap above the search
//  bar on every launch where the banner is not showing.
//

import SwiftUI
import UserNotifications
import UIKit

// MARK: - State

@Observable
@MainActor
final class PushReauthPrompt {
    static let shared = PushReauthPrompt()

    /// Dismissal is stored in UserDefaults, which iOS wipes along with the
    /// app — so "not now" holds for this install, and a later reinstall asks
    /// again, which is exactly the case this prompt exists for.
    private static let dismissedKey = "gs.pushReauthBannerDismissed"

    private(set) var isVisible: Bool = false
    private(set) var isRequesting: Bool = false

    private var dismissed: Bool {
        get { UserDefaults.standard.bool(forKey: Self.dismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.dismissedKey) }
    }

    private init() {}

    /// Reads the same two facts as `NotificationsSettingsView`'s
    /// `refreshSystemStatus()` — saved intent and the live iOS grant — so the
    /// two surfaces can never disagree about whether push is really on.
    func refresh() async {
        let status = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
        let wants = AuthViewModel.shared.notifyPushEnabled
        isVisible = wants && status == .notDetermined && !dismissed
    }

    func dismiss() {
        dismissed = true
        isVisible = false
    }

    /// Same path as the settings master toggle: ask iOS, and on a grant
    /// register for remote notifications so `push_tokens` picks up this
    /// install's APNs token instead of the deleted one's dead token.
    func requestAuthorization() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
            AuthViewModel.shared.setNotificationPreferences(push: true, sms: false)
            isVisible = false
        } else {
            // They were asked and said no. Record that as their intent and stop
            // asking; Profile → Notifications still explains how to turn it on.
            AuthViewModel.shared.setNotificationPreferences(push: false, sms: false)
            dismiss()
        }
    }
}

// MARK: - Observation

private struct PushReauthObserver: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth = AuthViewModel.shared

    func body(content: Content) -> some View {
        content
            .task { await PushReauthPrompt.shared.refresh() }
            // Permission can be granted in iOS Settings without the button
            // ever being tapped, so re-check on every return to the front.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await PushReauthPrompt.shared.refresh() }
            }
            // Intent arrives from the server after sign-in, which usually
            // lands after Home has already appeared.
            .onChange(of: auth.notifyPushEnabled) { _, _ in
                Task { await PushReauthPrompt.shared.refresh() }
            }
    }
}

extension View {
    /// Keeps `PushReauthPrompt.shared` current. Apply once, to a view that
    /// stays mounted for as long as Home does — not to the banner itself,
    /// which is conditional.
    func pushReauthObserver() -> some View {
        modifier(PushReauthObserver())
    }
}

// MARK: - View

struct PushReauthBanner: View {
    @State private var prompt = PushReauthPrompt.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("Turn notifications back on")
                    .scaledFont(size: 14, weight: .bold)
                    .foregroundStyle(.white)
                Text("Push is off on this device. Your alert types are still saved.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await prompt.requestAuthorization() }
                } label: {
                    Text(prompt.isRequesting ? "Turning on…" : "Turn back on")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.orange.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .disabled(prompt.isRequesting)
                .padding(.top, 6)
            }

            Spacer(minLength: 0)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                prompt.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.30), lineWidth: 1)
        )
    }
}
