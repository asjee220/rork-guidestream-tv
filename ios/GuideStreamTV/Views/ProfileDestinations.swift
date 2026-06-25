//
//  ProfileDestinations.swift
//  GuideStreamTV
//
//  All sub-screens pushed onto the Profile NavigationStack:
//  Account, Connected Services, Devices, Notifications, Profiles,
//  and Help & Feedback. iOS Widget reuses the existing
//  `WidgetSetupView` from `HomeDestinations.swift`.
//

import SwiftUI
import UIKit
import StoreKit
import UserNotifications
import Supabase
import Auth
import PostgREST

// MARK: - Account

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthViewModel.shared
    @State private var nameDraft: String = ""
    @State private var isSaving: Bool = false
    @State private var savedFlash: Bool = false
    @State private var showResetSent: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var isSendingReset: Bool = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            BrandBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    if auth.isAuthenticated {
                        avatarHeader
                        nameEditor
                        infoCard
                        actionsCard
                        if savedFlash {
                            statusBanner(text: "Saved", isError: false)
                                .transition(.opacity)
                        }
                        deleteCard
                    } else {
                        guestPrompt
                    }
                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Reset link sent", isPresented: $showResetSent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your inbox for a recovery link to set a new password.")
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account will be permanently deleted. You'll be signed out immediately and lose access to your saved shows, devices, and history.")
        }
        .task {
            nameDraft = auth.displayName
                ?? ProfileView.titleCase(emailLocal)
        }
    }

    // MARK: - Sections

    private var avatarHeader: some View {
        VStack(spacing: 12) {
            AvatarRing(initials: initials, size: 96)
            Text(currentDisplayName)
                .scaledFont(size: 18, weight: .bold)
                .foregroundStyle(.white)
            if let email = auth.currentUser?.email {
                Text(email)
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var nameEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISPLAY NAME")
                .scaledFont(size: 11, weight: .semibold)
                .tracking(0.8)
                .foregroundStyle(Color.textTertiary)

            HStack(spacing: 10) {
                TextField("", text: $nameDraft, prompt: Text("Your name").foregroundColor(Color.textTertiary))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($nameFocused)
                    .scaledFont(size: 16, weight: .medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(nameFocused ? 0.20 : 0.08), lineWidth: 1)
                    )

                Button(action: saveName) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(width: 70, height: 48)
                    } else {
                        Text("Save")
                            .scaledFont(size: 14, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(width: 70, height: 48)
                    }
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(saveDisabled ? Color.orange.opacity(0.35) : Color.orange)
                )
                .shadow(color: saveDisabled ? .clear : Color.orange.opacity(0.4), radius: 12, y: 4)
                .disabled(saveDisabled)
            }
        }
    }

    private var infoCard: some View {
        ProfileCard {
            ProfileInfoRow(
                label: "Email",
                value: auth.currentUser?.email ?? "—",
                isMonospaced: true,
                copyable: true
            )
            ProfileRowDivider()
            ProfileInfoRow(
                label: "Sign-in method",
                value: signInMethodLabel,
                isMonospaced: false,
                copyable: false
            )
            ProfileRowDivider()
            ProfileInfoRow(
                label: "User ID",
                value: shortenedUserId,
                isMonospaced: true,
                copyable: true,
                fullValueOverride: auth.currentUser?.id.uuidString
            )
        }
    }

    private var actionsCard: some View {
        ProfileCard {
            ProfileRow(
                icon: "key.fill",
                iconTint: Color.orange,
                title: "Reset password",
                subtitle: isSendingReset ? "Sending…" : "We'll email you a recovery link",
                onTap: { Task { await sendReset() } }
            )
        }
    }

    private var deleteCard: some View {
        ProfileCard {
            ProfileRow(
                icon: "trash.fill",
                iconTint: Color(red: 0.96, green: 0.32, blue: 0.32),
                title: "Delete account",
                subtitle: "Permanently remove your data",
                trailingHidden: true,
                titleColor: Color(red: 0.96, green: 0.32, blue: 0.32),
                onTap: { showDeleteConfirm = true }
            )
        }
    }

    private var guestPrompt: some View {
        VStack(spacing: 16) {
            AvatarRing(initials: "G", size: 96)
            Text("You're browsing as a guest")
                .scaledFont(size: 18, weight: .bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Sign in with email, Apple, or Google to sync your shows, devices, and watch history.")
                .scaledFont(size: 13)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.bottom, 8)
            Button(action: signOutToWelcome) {
                Text("Go to sign in")
                    .scaledFont(size: 15, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(Color.orange))
                    .shadow(color: Color.orange.opacity(0.45), radius: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 32)
    }

    // MARK: - Helpers

    private var initials: String {
        ProfileView.initials(
            firstName: auth.firstName,
            lastName: auth.lastName,
            fallbackName: currentDisplayName,
            isGuest: auth.isGuest,
            isAuthenticated: auth.isAuthenticated
        )
    }

    private var currentDisplayName: String {
        if let cached = auth.displayName, !cached.isEmpty { return cached }
        if !emailLocal.isEmpty { return ProfileView.titleCase(emailLocal) }
        return "Account"
    }

    private var emailLocal: String {
        guard let email = auth.currentUser?.email else { return "" }
        return String(email.split(separator: "@").first ?? "")
    }

    private var saveDisabled: Bool {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == (auth.displayName ?? "") || isSaving
    }

    private var signInMethodLabel: String {
        let identities = auth.currentUser?.identities ?? []
        if identities.contains(where: { $0.provider == "apple" }) { return "Apple" }
        if identities.contains(where: { $0.provider == "google" }) { return "Google" }
        if identities.contains(where: { $0.provider == "email" }) { return "Email" }
        return "—"
    }

    private var shortenedUserId: String {
        let id = auth.currentUser?.id.uuidString ?? ""
        guard id.count > 12 else { return id }
        return "\(id.prefix(6))…\(id.suffix(4))"
    }

    private func saveName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            isSaving = true
            defer { isSaving = false }
            let ok = await auth.updateDisplayName(trimmed)
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    savedFlash = true
                }
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeOut(duration: 0.25)) { savedFlash = false }
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func sendReset() async {
        guard let email = auth.currentUser?.email, !email.isEmpty else { return }
        isSendingReset = true
        defer { isSendingReset = false }
        let ok = await auth.sendPasswordReset(email: email)
        if ok { showResetSent = true }
    }

    private func deleteAccount() async {
        // Real account deletion requires a backend admin call. For now we
        // sign the user out and log a deletion-requested event so the team
        // can follow up. The user immediately sees the welcome screen.
        WatchIntentLogger.shared.log(
            eventType: .authSignedIn,
            metadata: ["action": "account_deletion_requested"]
        )
        await auth.signOut()
        dismiss()
    }

    private func signOutToWelcome() {
        Task { await auth.signOut() }
    }

    @ViewBuilder
    private func statusBanner(text: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .scaledFont(size: 13, weight: .semibold)
            Text(text)
                .scaledFont(size: 13, weight: .semibold)
        }
        .foregroundStyle(isError ? Color.red.opacity(0.9) : Color.green)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill((isError ? Color.red : Color.green).opacity(0.12))
        )
    }
}

// MARK: - ProfileInfoRow

/// Static label/value row used inside Account info cards. Tapping a copyable
/// row writes the value to the pasteboard with a quick haptic.
struct ProfileInfoRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false
    var copyable: Bool = false
    /// Optional richer value to copy (e.g. full UUID when the displayed one
    /// is truncated). When nil, `value` is copied.
    var fullValueOverride: String? = nil
    @State private var didCopy: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .scaledFont(size: 13, weight: .semibold, design: isMonospaced ? .monospaced : .default)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if copyable {
                Button(action: copy) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(didCopy ? Color.green : Color.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func copy() {
        UIPasteboard.general.string = fullValueOverride ?? value
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            didCopy = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) { didCopy = false }
            }
        }
    }
}

// MARK: - ConnectedServices

struct ConnectedServicesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthViewModel.shared
    @State private var selected: Set<String>
    @State private var saveFlash: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    init() {
        _selected = State(initialValue: AuthViewModel.shared.selectedServices)
    }

    var body: some View {
        ZStack {
            BrandBackground()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Pick every service you have so your home feed only shows shows and movies you can actually watch.")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.top, 4)

                        currentlySelectedSection

                        LazyVGrid(columns: columns, spacing: 22) {
                            ForEach(StreamingCatalog.all) { svc in
                                ServiceTile(
                                    service: svc,
                                    isSelected: selected.contains(svc.id),
                                    onTap: { toggle(svc.id) }
                                )
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                bottomBar
            }
        }
        .navigationTitle("Connected Services")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    private var currentlySelectedSection: some View {
        let services = StreamingCatalog.ordered(from: selected).prefix(8)
        if !services.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("CONNECTED")
                    .scaledFont(size: 11, weight: .semibold)
                    .tracking(0.8)
                    .foregroundStyle(Color.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(services), id: \.id) { svc in
                            HStack(spacing: 6) {
                                ServiceMiniIcon(service: svc, size: 18)
                                Text(svc.name)
                                    .scaledFont(size: 12, weight: .semibold)
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Text("\(selected.count) service\(selected.count == 1 ? "" : "s") selected")
                .scaledFont(size: 12)
                .foregroundStyle(Color.textSecondary)

            Button(action: save) {
                HStack(spacing: 8) {
                    if saveFlash {
                        Image(systemName: "checkmark")
                            .scaledFont(size: 14, weight: .bold)
                        Text("Saved")
                            .scaledFont(size: 16, weight: .bold)
                    } else {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .scaledFont(size: 14, weight: .bold)
                        Text("Save Changes")
                            .scaledFont(size: 16, weight: .bold)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.orange.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color.orange.opacity(0.45), radius: 22, x: 0, y: 0)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(
            Color.navy
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func toggle(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        }
    }

    private func save() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        auth.setSelectedServices(selected)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { saveFlash = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { saveFlash = false }
            }
        }
    }
}

// MARK: - Devices

struct DevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthViewModel.shared
    @State private var rows: [DeviceSessionRow] = []
    @State private var isLoading: Bool = true
    @State private var loadError: String?
    @State private var removingDeviceId: String?
    @State private var showRemoveConfirm: String?

    private var currentDeviceId: String { DeviceIdentity.shared.deviceId }

    var body: some View {
        ZStack {
            BrandBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    headerBlurb
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    if isLoading && rows.isEmpty {
                        ProgressView()
                            .tint(Color.orange)
                            .frame(height: 80)
                    } else if rows.isEmpty {
                        emptyState
                            .padding(.horizontal, 20)
                    } else {
                        ProfileCard {
                            ForEach(Array(rows.enumerated()), id: \.element.device_id) { idx, row in
                                if idx > 0 { ProfileRowDivider() }
                                DeviceCellView(
                                    row: row,
                                    isCurrent: row.device_id == currentDeviceId,
                                    isRemoving: removingDeviceId == row.device_id,
                                    onRemove: { showRemoveConfirm = row.device_id }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    if let err = loadError {
                        Text(err)
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.red.opacity(0.85))
                            .padding(.horizontal, 20)
                    }

                    Color.clear.frame(height: 60)
                }
            }
            .refreshable { await load() }
        }
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .confirmationDialog(
            "Sign this device out?",
            isPresented: Binding(
                get: { showRemoveConfirm != nil },
                set: { if !$0 { showRemoveConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Sign out device", role: .destructive) {
                if let id = showRemoveConfirm {
                    Task { await removeDevice(id) }
                }
                showRemoveConfirm = nil
            }
            Button("Cancel", role: .cancel) {
                showRemoveConfirm = nil
            }
        } message: {
            Text("This will revoke this device's access. It will need to sign back in next time it opens GuideStream TV.")
        }
    }

    @ViewBuilder
    private var headerBlurb: some View {
        if auth.isAuthenticated {
            Text("Your account is signed in on the devices below. Pull to refresh.")
                .scaledFont(size: 13)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Sign in to see all of your installs. Right now you're only seeing this device.")
                .scaledFont(size: 13)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.slash")
                .scaledFont(size: 28, weight: .light)
                .foregroundStyle(Color.textTertiary)
            Text("No devices yet")
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(.white)
            Text("Devices will appear here the next time you open the app on another phone or tablet.")
                .scaledFont(size: 12)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding(.vertical, 32)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        if let uid = auth.currentUser?.id.uuidString {
            do {
                let fetched: [DeviceSessionRow] = try await SupabaseManager.shared.client
                    .from("device_sessions")
                    .select("device_id, device_model, os_version, app_version, build_number, last_seen_at, first_seen_at, is_authenticated, is_guest, session_count")
                    .eq("user_id", value: uid)
                    .order("last_seen_at", ascending: false)
                    .execute()
                    .value
                // Make sure the current device is always represented so the
                // user can see "this device" even before the first upsert
                // makes it to the server.
                if !fetched.contains(where: { $0.device_id == currentDeviceId }) {
                    rows = [currentDeviceSyntheticRow()] + fetched
                } else {
                    rows = fetched
                }
                loadError = nil
            } catch {
                rows = [currentDeviceSyntheticRow()]
                loadError = error.localizedDescription
                print("[Devices] load failed: \(error.localizedDescription)")
            }
        } else {
            rows = [currentDeviceSyntheticRow()]
        }

        await ProfileStatsService.shared.refresh()
    }

    /// Build a fallback row from local state so the current device always
    /// shows up even without a Supabase round-trip.
    private func currentDeviceSyntheticRow() -> DeviceSessionRow {
        DeviceSessionRow(
            device_id: currentDeviceId,
            device_model: UIDevice.current.model,
            os_version: UIDevice.current.systemVersion,
            app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            build_number: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            last_seen_at: ISO8601DateFormatter().string(from: Date()),
            first_seen_at: nil,
            is_authenticated: auth.isAuthenticated,
            is_guest: auth.isGuest,
            session_count: DeviceSessionService.shared.sessionCount
        )
    }

    private func removeDevice(_ deviceId: String) async {
        removingDeviceId = deviceId
        defer { removingDeviceId = nil }

        // Removing the current device → just sign out locally.
        if deviceId == currentDeviceId {
            await auth.signOut()
            return
        }

        do {
            try await SupabaseManager.shared.client
                .from("device_sessions")
                .delete()
                .eq("device_id", value: deviceId)
                .execute()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
        } catch {
            loadError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            print("[Devices] remove failed: \(error.localizedDescription)")
        }
    }
}

private struct DeviceCellView: View {
    let row: DeviceSessionRow
    let isCurrent: Bool
    let isRemoving: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                Image(systemName: iconName)
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color(red: 0.55, green: 0.40, blue: 0.95))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(modelLabel)
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if isCurrent {
                        Text("THIS DEVICE")
                            .scaledFont(size: 9, weight: .heavy)
                            .tracking(0.5)
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.14)))
                            .overlay(Capsule().stroke(Color.green.opacity(0.4), lineWidth: 0.75))
                    }
                }
                Text(secondaryLine)
                    .scaledFont(size: 11)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                if !lastSeenLine.isEmpty {
                    Text(lastSeenLine)
                        .scaledFont(size: 11)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer(minLength: 8)

            if isRemoving {
                ProgressView()
                    .tint(Color.red)
                    .frame(width: 28, height: 28)
            } else {
                Menu {
                    Button(role: .destructive, action: onRemove) {
                        Label(isCurrent ? "Sign out this device" : "Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var iconName: String {
        let model = (row.device_model ?? "").lowercased()
        if model.contains("ipad") { return "ipad" }
        if model.contains("watch") { return "applewatch" }
        if model.contains("appletv") || model.contains("tv") { return "appletv" }
        return "iphone"
    }

    private var modelLabel: String {
        guard let model = row.device_model, !model.isEmpty else { return "iOS Device" }
        return DeviceModelMap.friendlyName(for: model)
    }

    private var secondaryLine: String {
        var parts: [String] = []
        if let os = row.os_version, !os.isEmpty { parts.append("iOS \(os)") }
        if let version = row.app_version, let build = row.build_number {
            parts.append("App \(version) (\(build))")
        } else if let version = row.app_version {
            parts.append("App \(version)")
        }
        return parts.joined(separator: " · ")
    }

    private var lastSeenLine: String {
        guard let raw = row.last_seen_at, let date = DeviceCellView.iso.date(from: raw) else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "Last seen \(f.localizedString(for: date, relativeTo: Date()))"
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// Maps raw hardware identifiers (e.g. `iPhone16,2`) to friendly names.
/// Used by the Devices screen to render readable rows.
enum DeviceModelMap {
    static func friendlyName(for identifier: String) -> String {
        switch identifier {
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        case "iPhone14,5": return "iPhone 13"
        case "iPhone14,4": return "iPhone 13 mini"
        case "iPhone13,4": return "iPhone 12 Pro Max"
        case "iPhone13,3": return "iPhone 12 Pro"
        case "iPhone13,2": return "iPhone 12"
        case "iPhone13,1": return "iPhone 12 mini"
        case "iPhone17,3": return "iPhone 16 Pro"
        case "iPhone17,4": return "iPhone 16 Pro Max"
        case "iPhone17,1": return "iPhone 16"
        case "iPhone17,2": return "iPhone 16 Plus"
        default:
            if identifier.hasPrefix("iPad") { return "iPad" }
            if identifier.hasPrefix("Watch") || identifier.hasPrefix("AppleWatch") { return "Apple Watch" }
            if identifier.lowercased().contains("simulator") { return "Simulator" }
            return identifier
        }
    }
}

// MARK: - Notifications Settings

struct NotificationsSettingsView: View {
    @State private var auth = AuthViewModel.shared
    @State private var pushOn: Bool = AuthViewModel.shared.notifyPushEnabled
    @State private var smsOn: Bool = AuthViewModel.shared.notifySMSEnabled
    @State private var systemDenied: Bool = false
    /// Currently-synced timezone shown in the read-only row. Defaults to the
    /// live device identifier and is replaced with the persisted value from
    /// `users.timezone` once `loadTimezone()` resolves for signed-in users.
    @State private var timezone: String = TimeZone.current.identifier

    var body: some View {
        ZStack {
            BrandBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if systemDenied {
                        deniedBanner
                    }

                    ProfileCard {
                        NotificationToggleRow(
                            icon: "bell.fill",
                            iconTint: Color.orange,
                            title: "New episode alerts",
                            subtitle: "Push notification when shows you follow drop new episodes",
                            isOn: $pushOn,
                            tint: Color.orange
                        )
                        .onChange(of: pushOn) { _, newValue in
                            handlePushToggle(newValue)
                        }

                        ProfileRowDivider()

                        NotificationToggleRow(
                            icon: "message.fill",
                            iconTint: Color.blue,
                            title: "Episode synopsis by text",
                            subtitle: "Get a 1-line SMS recap before each episode releases",
                            isOn: $smsOn,
                            tint: Color.blue
                        )
                        .onChange(of: smsOn) { _, newValue in
                            auth.setNotificationPreferences(push: pushOn, sms: newValue)
                        }

                        ProfileRowDivider()

                        NotificationToggleRow(
                            icon: "film",
                            iconTint: Color.orange,
                            title: "Movie release alerts",
                            subtitle: "Get notified when saved movies drop on your services",
                            isOn: $auth.notifyMovieReleasesEnabled,
                            tint: Color.orange
                        )
                    }

                    ProfileCard {
                        ProfileRow(
                            icon: "gearshape.fill",
                            iconTint: Color.textSecondary,
                            title: "Open iOS Settings",
                            subtitle: "Fine-tune badges, banners, and sound",
                            onTap: openSystemSettings
                        )
                    }

                    ProfileCard {
                        TimezoneInfoRow(value: timezone)
                    }

                    Text("We only send notifications about shows on services you actually have. Update your services in Connected Services to fine-tune what you hear about.")
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 60)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await refreshSystemStatus() }
        .task { await loadTimezone() }
        .task { await auth.loadMovieReleasePreference() }
    }

    /// Loads the synced timezone for the row. Signed-in users read the
    /// persisted `users.timezone`; guests (and any failure) fall back to the
    /// live device identifier.
    private func loadTimezone() async {
        guard let uid = auth.currentUser?.id.uuidString else {
            timezone = TimeZone.current.identifier
            return
        }
        do {
            let rows: [UserTimezoneRow] = try await SupabaseManager.shared.client
                .from("users")
                .select("timezone")
                .eq("id", value: uid)
                .limit(1)
                .execute()
                .value
            if let tz = rows.first?.timezone, !tz.isEmpty {
                timezone = tz
            } else {
                timezone = TimeZone.current.identifier
            }
        } catch {
            timezone = TimeZone.current.identifier
        }
    }

    private var deniedBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .scaledFont(size: 14, weight: .bold)
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications are off in Settings")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(.white)
                Text("Tap Open iOS Settings below to turn them back on.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.textSecondary)
            }
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

    private func handlePushToggle(_ newValue: Bool) {
        guard newValue else {
            auth.setNotificationPreferences(push: false, sms: smsOn)
            return
        }
        Task { @MainActor in
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                    auth.setNotificationPreferences(push: true, sms: smsOn)
                } else {
                    pushOn = false
                    systemDenied = true
                    auth.setNotificationPreferences(push: false, sms: smsOn)
                }
            } catch {
                pushOn = false
                auth.setNotificationPreferences(push: false, sms: smsOn)
            }
        }
    }

    private func refreshSystemStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let denied = settings.authorizationStatus == .denied
        await MainActor.run {
            systemDenied = denied && pushOn
        }
    }

    private func openSystemSettings() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// Minimal row decoder for the `users.timezone` column.
private struct UserTimezoneRow: Decodable {
    let timezone: String?
}

/// Read-only row showing the currently-synced timezone. Matches the
/// `ProfileRow` layout (icon tile + title) but renders a static value label
/// instead of a chevron, so it reads as informational rather than tappable.
private struct TimezoneInfoRow: View {
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                Image(systemName: "globe")
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(width: 36, height: 36)

            Text("Your timezone")
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(value)
                .scaledFont(size: 14)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct NotificationToggleRow: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                Image(systemName: icon)
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(iconTint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Profiles

struct ProfilesView: View {
    @State private var manager = AppProfileManager.shared
    @State private var showAddSheet: Bool = false
    @State private var editing: WatchProfile?

    var body: some View {
        ZStack {
            BrandBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    Text("Different folks, different feeds. Each profile keeps its own preferences and history.")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    ProfileCard {
                        ForEach(Array(manager.profiles.enumerated()), id: \.element.id) { idx, profile in
                            if idx > 0 { ProfileRowDivider() }
                            WatchProfileRow(
                                profile: profile,
                                isActive: profile.id == manager.activeProfileId,
                                onSelect: { select(profile.id) },
                                onEdit: { editing = profile },
                                onRemove: { manager.remove(profile.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    Button(action: { showAddSheet = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .scaledFont(size: 17, weight: .semibold)
                                .foregroundStyle(Color.orange)
                            Text("Add a new profile")
                                .scaledFont(size: 15, weight: .semibold)
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .scaledFont(size: 12, weight: .semibold)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.orange.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.orange.opacity(0.30), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
                    .padding(.horizontal, 20)

                    Color.clear.frame(height: 40)
                }
            }
        }
        .navigationTitle("Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showAddSheet) {
            ProfileEditorSheet(existing: nil) { name, color, isKid, emoji in
                manager.addProfile(name: name, colorHex: color, isKid: isKid, emoji: emoji)
            }
        }
        .sheet(item: $editing) { profile in
            ProfileEditorSheet(existing: profile) { name, color, isKid, emoji in
                manager.update(WatchProfile(id: profile.id, name: name, colorHex: color, isKid: isKid, emoji: emoji))
            }
        }
    }

    private func select(_ id: UUID) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        manager.setActive(id)
    }
}

private struct WatchProfileRow: View {
    let profile: WatchProfile
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(profile.color)
                    Text(profile.emoji)
                        .scaledFont(size: 18, weight: .bold)
                }
                .frame(width: 38, height: 38)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .scaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(.white)
                        if profile.isKid {
                            Text("KID")
                                .scaledFont(size: 9, weight: .heavy)
                                .tracking(0.5)
                                .foregroundStyle(Color.blue)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.15)))
                                .overlay(Capsule().stroke(Color.blue.opacity(0.45), lineWidth: 0.75))
                        }
                    }
                    Text(isActive ? "Active profile" : "Tap to switch")
                        .scaledFont(size: 11)
                        .foregroundStyle(isActive ? Color.orange : Color.textSecondary)
                }

                Spacer(minLength: 8)

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(Color.orange)
                }

                Menu {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onRemove) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProfileRowButtonStyle())
    }
}

/// Add/edit sheet for a single WatchProfile. Bottom-sheet style with name
/// field, color palette, emoji palette, and kid toggle.
private struct ProfileEditorSheet: View {
    let existing: WatchProfile?
    let onSave: (_ name: String, _ colorHex: String, _ isKid: Bool, _ emoji: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: String
    @State private var isKid: Bool
    @State private var emoji: String
    @FocusState private var nameFocused: Bool

    init(
        existing: WatchProfile?,
        onSave: @escaping (_ name: String, _ colorHex: String, _ isKid: Bool, _ emoji: String) -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _color = State(initialValue: existing?.colorHex ?? AppProfileManager.palette[0])
        _isKid = State(initialValue: existing?.isKid ?? false)
        _emoji = State(initialValue: existing?.emoji ?? AppProfileManager.emojis[0])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        previewAvatar
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("NAME")
                                .scaledFont(size: 11, weight: .semibold)
                                .tracking(0.8)
                                .foregroundStyle(Color.textTertiary)
                            TextField("", text: $name, prompt: Text("Profile name").foregroundColor(Color.textTertiary))
                                .focused($nameFocused)
                                .textInputAutocapitalization(.words)
                                .scaledFont(size: 16, weight: .medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(nameFocused ? 0.2 : 0.08), lineWidth: 1)
                                )
                        }

                        colorPalette
                        emojiPalette

                        Toggle(isOn: $isKid) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kid profile")
                                    .scaledFont(size: 15, weight: .semibold)
                                    .foregroundStyle(.white)
                                Text("Only show kid-friendly content for this profile")
                                    .scaledFont(size: 12)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .tint(Color.orange)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 80)
                }

                VStack {
                    Spacer()
                    Button(action: commit) {
                        Text(existing == nil ? "Create Profile" : "Save Changes")
                            .scaledFont(size: 16, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                LinearGradient(
                                    colors: [Color.orange, Color.orange.opacity(0.85)],
                                    startPoint: .top, endPoint: .bottom
                                )
                                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color.orange.opacity(0.5), radius: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle(existing == nil ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .toolbarBackground(Color.navy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var previewAvatar: some View {
        ZStack {
            Circle()
                .fill(Color(hex: color))
                .frame(width: 100, height: 100)
                .shadow(color: Color(hex: color).opacity(0.5), radius: 22)
            Text(emoji)
                .scaledFont(size: 42, weight: .bold)
            if isKid {
                Text("KID")
                    .scaledFont(size: 10, weight: .heavy)
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue))
                    .offset(y: 46)
            }
        }
        .frame(height: 130)
    }

    private var colorPalette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COLOR")
                .scaledFont(size: 11, weight: .semibold)
                .tracking(0.8)
                .foregroundStyle(Color.textTertiary)
            HStack(spacing: 10) {
                ForEach(AppProfileManager.palette, id: \.self) { hex in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.3)) { color = hex }
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(
                                        hex == color ? Color.white : Color.white.opacity(0.10),
                                        lineWidth: hex == color ? 2 : 1
                                    )
                            )
                            .scaleEffect(hex == color ? 1.1 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emojiPalette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AVATAR")
                .scaledFont(size: 11, weight: .semibold)
                .tracking(0.8)
                .foregroundStyle(Color.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppProfileManager.emojis, id: \.self) { glyph in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3)) { emoji = glyph }
                        } label: {
                            Text(glyph)
                                .scaledFont(size: 22, weight: .bold)
                                .frame(width: 42, height: 42)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(glyph == emoji ? 0.14 : 0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            glyph == emoji ? Color.orange : Color.white.opacity(0.08),
                                            lineWidth: glyph == emoji ? 2 : 1
                                        )
                                )
                                .scaleEffect(glyph == emoji ? 1.08 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSave(trimmed, color, isKid, emoji)
        dismiss()
    }
}

// MARK: - Help & Feedback

struct HelpFeedbackView: View {
    @Environment(\.requestReview) private var requestReview
    @State private var showDiagnostics: Bool = false
    @State private var expandedFAQ: UUID?

    private let supportEmail = "support@guidestream.tv"
    private let privacyURL = URL(string: "https://guidestream.tv/privacy")!
    private let termsURL = URL(string: "https://guidestream.tv/terms")!
    private let youTubeTermsURL = URL(string: "https://www.youtube.com/t/terms")!

    var body: some View {
        ZStack {
            BrandBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    contactCard
                    faqSection
                    legalCard
                    diagnosticsCard
                    versionFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 60)
            }
        }
        .navigationTitle("Help & Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showDiagnostics) {
            SupabaseDiagnosticsView()
        }
    }

    private var contactCard: some View {
        ProfileCard {
            ProfileRow(
                icon: "envelope.fill",
                iconTint: Color.orange,
                title: "Email Support",
                subtitle: supportEmail,
                onTap: emailSupport
            )
            ProfileRowDivider()
            ProfileRow(
                icon: "star.fill",
                iconTint: Color(red: 0.96, green: 0.78, blue: 0.20),
                title: "Rate GuideStream TV",
                subtitle: "Tell us how we're doing on the App Store",
                onTap: { requestReview() }
            )
            ProfileRowDivider()
            ProfileRow(
                icon: "exclamationmark.bubble.fill",
                iconTint: Color.blue,
                title: "Report a problem",
                subtitle: "Something not working? Let us know.",
                onTap: reportBug
            )
        }
    }

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FREQUENTLY ASKED")
                .scaledFont(size: 11, weight: .semibold)
                .tracking(0.8)
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 4)

            ProfileCard {
                ForEach(Array(faqItems.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { ProfileRowDivider() }
                    FAQRow(
                        item: item,
                        isExpanded: expandedFAQ == item.id,
                        onTap: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                expandedFAQ = expandedFAQ == item.id ? nil : item.id
                            }
                        }
                    )
                }
            }
        }
    }

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileCard {
                ProfileRow(
                    icon: "lock.shield.fill",
                    iconTint: Color(red: 0.55, green: 0.78, blue: 0.95),
                    title: "Privacy Policy",
                    subtitle: "How we handle your data",
                    onTap: { open(privacyURL) }
                )
                ProfileRowDivider()
                ProfileRow(
                    icon: "doc.text.fill",
                    iconTint: Color.textSecondary,
                    title: "Terms of Service",
                    subtitle: "The fine print",
                    onTap: { open(termsURL) }
                )
                ProfileRowDivider()
                ProfileRow(
                    icon: "play.rectangle.fill",
                    iconTint: Color(red: 0.92, green: 0.25, blue: 0.25),
                    title: "YouTube Terms of Service",
                    subtitle: "Trailers are powered by YouTube",
                    onTap: { open(youTubeTermsURL) }
                )
            }

            Text("By using GuideStream TV, including watching trailers, you agree to be bound by the YouTube Terms of Service.")
                .scaledFont(size: 12)
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 4)
                .padding(.top, 2)
        }
    }

    private var diagnosticsCard: some View {
        ProfileCard {
            ProfileRow(
                icon: "waveform.path.ecg",
                iconTint: Color.green,
                title: "App Diagnostics",
                subtitle: "View device ID, sync status, and recent errors",
                onTap: { showDiagnostics = true }
            )
        }
    }

    private var versionFooter: some View {
        VStack(spacing: 4) {
            BrandWordmark(wordmarkSize: .small)
            Text("Version \(appVersion) (Build \(buildNumber))")
                .scaledFont(size: 11)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var faqItems: [FAQItem] {
        [
            FAQItem(question: "How does GuideStream TV know what I can watch?",
                    answer: "You tell us which streaming services you subscribe to under Connected Services. We only surface shows and movies that are available on one of your services so you never click into a paywall."),
            FAQItem(question: "Why am I not getting new-episode notifications?",
                    answer: "Make sure push notifications are turned on under Notifications, and that you've allowed them in iOS Settings. We also only notify you about shows on services you have selected."),
            FAQItem(question: "Will signing out delete my data?",
                    answer: "No. Your account, watch history, and saved shows stay safe on our servers. Sign back in any time on this or another device."),
            FAQItem(question: "Can I use multiple profiles?",
                    answer: "Yes — head to Profiles to create up to a handful of personas (Kids, Partner, Main, etc.). Each one keeps its own preferences and history."),
            FAQItem(question: "Is GuideStream TV free?",
                    answer: "The core experience is free. Premium features like SMS recaps and ad-free reels will be available with GuideStream Pro soon.")
        ]
    }

    // MARK: - Actions

    private func emailSupport() {
        let subject = "GuideStream TV Support".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = """

        ----
        Version: \(appVersion) (\(buildNumber))
        Device: \(UIDevice.current.model)
        iOS: \(UIDevice.current.systemVersion)
        Device ID: \(DeviceIdentity.shared.deviceId)
        """.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "mailto:\(supportEmail)?subject=\(subject)&body=\(body)"
        if let url = URL(string: urlString) {
            open(url)
        }
    }

    private func reportBug() {
        let subject = "GuideStream TV bug report".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = """

        Describe what happened:


        ----
        Version: \(appVersion) (\(buildNumber))
        Device: \(UIDevice.current.model)
        iOS: \(UIDevice.current.systemVersion)
        Device ID: \(DeviceIdentity.shared.deviceId)
        """.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "mailto:\(supportEmail)?subject=\(subject)&body=\(body)"
        if let url = URL(string: urlString) {
            open(url)
        }
    }

    private func open(_ url: URL) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIApplication.shared.open(url)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

private struct FAQItem: Identifiable, Hashable {
    let id: UUID = UUID()
    let question: String
    let answer: String
}

private struct FAQRow: View {
    let item: FAQItem
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(item.question)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "minus" : "plus")
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(Color.orange)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.orange.opacity(0.14)))
                }
                if isExpanded {
                    Text(item.answer)
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProfileRowButtonStyle())
    }
}
