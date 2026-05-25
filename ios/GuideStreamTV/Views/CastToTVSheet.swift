//
//  CastToTVSheet.swift
//  GuideStreamTV
//
//  Bottom sheet that scans the local network for Apple TV / Roku devices and
//  lets the user pick one. On selection, attempts a deep-link launch on the
//  chosen device (Roku ECP) or AirPlay-style routing for Apple TV, shows a
//  quick confirmation toast, then opens the appropriate remote-control app.
//

import SwiftUI
import UIKit

struct CastToTVSheet: View {
    @Binding var isPresented: Bool
    let showTitle: String
    let platform: String
    let tmdbId: Int?

    @State private var discovery: TVCastDiscovery = TVCastDiscovery()
    @State private var sendingDeviceId: String? = nil
    @State private var toast: ToastState? = nil
    @State private var showPermissionPrompt: Bool = false
    @State private var permissionCheckTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(Color(red: 0x0A/255, green: 0x10/255, blue: 0x1E/255))
        .overlay(alignment: .top) {
            if let toast { toastView(toast).padding(.top, 12) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(red: 0x0A/255, green: 0x10/255, blue: 0x1E/255))
        .onAppear { startScan() }
        .onDisappear {
            discovery.stop()
            permissionCheckTask?.cancel()
        }
    }

    // MARK: Header
    private var header: some View {
        VStack(spacing: 6) {
            Text("Play on TV")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Text(discovery.isScanning && discovery.devices.isEmpty
                 ? "Scanning your network…"
                 : "Choose a device to send \"\(showTitle)\"")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    // MARK: Content
    @ViewBuilder
    private var content: some View {
        if discovery.devices.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(discovery.devices) { device in
                        deviceRow(device)
                    }
                    rescanButton
                        .padding(.top, 6)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
    }

    /// `true` when the app is running in any iOS Simulator (including Rork's
    /// cloud preview). LAN discovery is impossible from a simulator because
    /// it isn't on the user's home Wi-Fi, so we surface a dedicated message
    /// rather than spinning forever.
    private var isRunningInSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill((showPermissionPrompt || isRunningInSimulator)
                          ? Color.orange.opacity(0.15)
                          : Color.white.opacity(0.06))
                    .frame(width: 80, height: 80)
                Image(systemName: isRunningInSimulator
                                  ? "iphone.gen3.radiowaves.left.and.right.slash"
                                  : (showPermissionPrompt ? "wifi.exclamationmark" : "wifi"))
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle((showPermissionPrompt || isRunningInSimulator)
                                     ? Color.orange
                                     : Color.white.opacity(0.6))
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
            }

            if isRunningInSimulator {
                Text("Install on your iPhone to cast")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("This preview runs in a cloud simulator that isn't on your home Wi-Fi, so it can't see your Apple TV or Roku. Install GuideStreamTV on your iPhone via the Rork app and open Play on TV there.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            } else if showPermissionPrompt {
                Text("Local Network access needed")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Open Settings → Privacy & Security → Local Network, then enable GuideStreamTV so it can discover your Apple TV or Roku on Wi-Fi.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                openSettingsButton
                rescanButton
            } else {
                Text("Looking for Apple TV & Roku…")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text("Make sure your phone and TV are on the same Wi-Fi network.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                rescanButton
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 36)
    }

    private var openSettingsButton: some View {
Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Try the private Privacy > Local Network deep link first so the
            // user lands on the exact toggle. Fall back to the app's own
            // Settings page (the only officially-supported path) if iOS
            // refuses to open the prefs URL.
            let localNetworkURL = URL(string: "App-Prefs:Privacy&path=LOCAL_NETWORK")
            let appSettingsURL = URL(string: UIApplication.openSettingsURLString)
            if let localNetworkURL, UIApplication.shared.canOpenURL(localNetworkURL) {
                UIApplication.shared.open(localNetworkURL)
            } else if let appSettingsURL {
                UIApplication.shared.open(appSettingsURL)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill")
                Text("Open Settings")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
    }

    private var rescanButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            startScan()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                Text("Rescan")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Device row
    private func deviceRow(_ device: DiscoveredTVDevice) -> some View {
        Button {
            handleSelect(device)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(device.kind == .appleTV
                              ? Color.white.opacity(0.10)
                              : Color(red: 0x66/255, green: 0x2D/255, blue: 0x91/255).opacity(0.35))
                        .frame(width: 46, height: 46)
                    Image(systemName: device.kind == .appleTV ? "appletv" : "tv.inset.filled")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(device.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                Spacer(minLength: 0)

                if sendingDeviceId == device.id {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(sendingDeviceId != nil)
    }

    // MARK: Toast
    private struct ToastState: Equatable {
        let message: String
        let icon: String
    }

    private func toastView(_ state: ToastState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: state.icon)
                .font(.system(size: 14, weight: .semibold))
            Text(state.message)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Scan lifecycle

    /// Starts a discovery scan and schedules a permission-prompt check. If no
    /// devices appear after a short window, iOS has either denied Local Network
    /// access or there's genuinely nothing on the LAN — either way, surfacing
    /// the "Open Settings" affordance is the right call.
    private func startScan() {
        showPermissionPrompt = false
        permissionCheckTask?.cancel()
        discovery.stop()

        // Skip scanning entirely in the cloud simulator — it can't reach the
        // user's home Wi-Fi, so the empty state explains what to do instead.
        guard !isRunningInSimulator else { return }

        discovery.start()

        permissionCheckTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if discovery.devices.isEmpty {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showPermissionPrompt = true
                }
            }
        }
    }

    // MARK: Actions
    private func handleSelect(_ device: DiscoveredTVDevice) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        sendingDeviceId = device.id

        WatchIntentLogger.shared.log(
            eventType: .playOnDeviceChosen,
            titleId: WatchIntentLogger.titleSlug(showTitle),
            platformId: platform.lowercased(),
            metadata: [
                "device_id": device.id,
                "device_kind": device.kind.rawValue,
                "device_name": device.name
            ]
        )

        Task {
            let ok = await dispatchLaunch(for: device)
            await MainActor.run {
                sendingDeviceId = nil
                showToast(ok
                          ? ToastState(message: "Sent to \(device.name)", icon: "checkmark.circle.fill")
                          : ToastState(message: "Couldn't reach \(device.name)", icon: "exclamationmark.triangle.fill"))
                // Brief delay so the user sees the confirmation, then open the
                // matching remote-control app and dismiss the sheet.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    openRemoteApp(for: device.kind)
                    isPresented = false
                }
            }
        }
    }

    private func dispatchLaunch(for device: DiscoveredTVDevice) async -> Bool {
        switch device.kind {
        case .roku:
            guard let host = device.host,
                  let port = device.port,
                  let channelId = RokuChannel.id(for: platform) else {
                return false
            }
            return await RokuECPClient.launch(
                host: host,
                port: port,
                channelId: channelId,
                contentId: tmdbId.map { String($0) }
            )
        case .appleTV:
            // No first-party API to push a third-party show to Apple TV from
            // an arbitrary app; opening the platform app on iPhone with
            // AirPlay set to this Apple TV is the supported path.
            await MainActor.run {
                StreamingDeepLinker.open(platform: platform, title: showTitle, tmdbId: tmdbId)
            }
            return true
        }
    }

    private func openRemoteApp(for kind: TVDeviceKind) {
        let url: URL?
        switch kind {
        case .appleTV:
            // The Apple TV Remote lives in Control Center on modern iOS; the
            // legacy standalone Remote app uses the `com.apple.tvremote` scheme.
            url = URL(string: "com.apple.tvremote://")
        case .roku:
            url = URL(string: "roku://")
        }
        guard let url else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            if !success, kind == .roku,
               let store = URL(string: "https://apps.apple.com/app/the-roku-app-official/id482066631") {
                UIApplication.shared.open(store)
            }
        }
    }

    private func showToast(_ state: ToastState) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = state }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }
}
