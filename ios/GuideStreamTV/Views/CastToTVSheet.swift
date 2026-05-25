//
//  CastToTVSheet.swift
//  GuideStreamTV
//
//  Bottom sheet that scans the local network for Apple TV / Roku devices and
//  lets the user pick one. On selection, attempts a deep-link launch on the
//  chosen device (Roku ECP) or AirPlay-style routing for Apple TV, shows a
//  quick confirmation toast, then opens the appropriate remote-control app.
//
//  When auto-discovery turns up nothing, the sheet falls back to a manual IP
//  entry so users on AP-isolated, VPN-routed, or multi-VLAN networks can still
//  cast. The diagnostic strip above the action buttons exposes the local IP,
//  scan progress, and Bonjour endpoints seen — making "nothing found" failures
//  actionable instead of opaque.
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
    @State private var isManualEntryExpanded: Bool = false
    @State private var manualHost: String = ""
    @State private var isProbingManual: Bool = false
    @FocusState private var manualFieldFocused: Bool

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
                    diagnosticsStrip
                        .padding(.top, 4)
                    manualEntrySection
                    rescanButton
                        .padding(.top, 2)
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

    /// `true` when the iPhone has a self-assigned (link-local) IPv4 address.
    /// iOS only assigns 169.254.x.x when DHCP fails — meaning the phone is
    /// associated with a Wi-Fi network but never got a real IP. In that state
    /// it can't reach any LAN device (Apple TV, Roku, anything), so we need to
    /// surface remediation steps rather than retry forever.
    private var phoneOnLinkLocal: Bool {
        guard let ip = discovery.localIPv4 else { return false }
        return ip.hasPrefix("169.254.")
    }

    /// `true` when no IPv4 address could be detected at all — usually means
    /// Wi-Fi is off or the phone is on cellular only.
    private var phoneHasNoIPv4: Bool {
        // We only treat "no IP" as a problem once the scan has had a chance
        // to detect one. Before the probe starts, localIPv4 is briefly nil.
        discovery.localIPv4 == nil && discovery.totalHosts > 0
    }

    private var emptyState: some View {
        ScrollView {
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
                } else if phoneOnLinkLocal {
                    Text("Your phone isn't on the Wi-Fi network")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                    Text("iPhone has a self-assigned address (\(discovery.localIPv4 ?? "169.254.x.x")) because the router didn't give it a real one. Until that's fixed, no app can see your Apple TV or Roku.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    linkLocalFixSteps
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                    HStack(spacing: 10) {
                        openWiFiSettingsButton
                        rescanButton
                    }
                } else if phoneHasNoIPv4 {
                    Text("Wi-Fi appears to be off")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Connect your iPhone to the same Wi-Fi network as your Apple TV or Roku, then come back and tap Rescan.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    HStack(spacing: 10) {
                        openWiFiSettingsButton
                        rescanButton
                    }
                } else if showPermissionPrompt {
                    Text("Couldn't find any devices yet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("If Local Network access is off, enable it in Settings. Some Wi-Fi networks block device-to-device traffic — you can add your TV by IP below to bypass that.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    HStack(spacing: 10) {
                        openSettingsButton
                        rescanButton
                    }
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

                if !isRunningInSimulator {
                    diagnosticsStrip
                        .padding(.top, 6)
                    manualEntrySection
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 36)
            .padding(.horizontal, 18)
        }
        .scrollDismissesKeyboard(.interactively)
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
                Text("Settings")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
    }

    /// Opens iOS Wi-Fi settings directly so the user can toggle Wi-Fi off/on
    /// or rejoin the network. Falls back to the app's settings page if iOS
    /// rejects the prefs URL.
    private var openWiFiSettingsButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let wifiURL = URL(string: "App-Prefs:WIFI")
            let appSettingsURL = URL(string: UIApplication.openSettingsURLString)
            if let wifiURL, UIApplication.shared.canOpenURL(wifiURL) {
                UIApplication.shared.open(wifiURL)
            } else if let appSettingsURL {
                UIApplication.shared.open(appSettingsURL)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wifi")
                Text("Wi-Fi Settings")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
    }

    /// Step-by-step remediation shown when the phone has a 169.254.x.x address.
    /// These are the standard fixes in order of likelihood, and all of them are
    /// safe — they won't lose user data or change network settings.
    private var linkLocalFixSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            fixStep(number: 1, text: "Open Settings → Wi-Fi and toggle Wi-Fi off, then back on.")
            fixStep(number: 2, text: "If that doesn't work, tap your network's (i) and choose \"Forget This Network\", then rejoin with the password.")
            fixStep(number: 3, text: "Still no luck? Restart your router — it usually means DHCP ran out of addresses.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }

    private func fixStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.orange.opacity(0.85)))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
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

    // MARK: Diagnostics strip

    private var diagnosticsStrip: some View {
        VStack(spacing: 6) {
            diagnosticsRow(
                icon: phoneOnLinkLocal ? "wifi.exclamationmark" : "wifi",
                label: "Phone IP",
                value: discovery.localIPv4 ?? "—",
                state: phoneOnLinkLocal
                    ? .warning
                    : (discovery.localIPv4 != nil ? .ok : .neutral),
                valueNote: phoneOnLinkLocal ? "link-local" : nil
            )
            diagnosticsRow(
                icon: "magnifyingglass",
                label: "Scanned",
                value: discovery.totalHosts > 0
                    ? "\(discovery.scannedHosts)/\(discovery.totalHosts) hosts"
                    : "starting…",
                state: discovery.scannedHosts > 0 ? .ok : .neutral
            )
            diagnosticsRow(
                icon: "antenna.radiowaves.left.and.right",
                label: "Bonjour",
                value: "\(discovery.bonjourEndpointsSeen) services seen",
                state: discovery.bonjourEndpointsSeen > 0 ? .ok : .neutral
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private enum DiagnosticRowState {
        case ok
        case warning
        case neutral

        var iconColor: Color {
            switch self {
            case .ok:      return Color.green.opacity(0.85)
            case .warning: return Color.orange
            case .neutral: return Color.white.opacity(0.4)
            }
        }
    }

    private func diagnosticsRow(
        icon: String,
        label: String,
        value: String,
        state: DiagnosticRowState,
        valueNote: String? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.iconColor)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let valueNote {
                    Text(valueNote)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.orange.opacity(0.15))
                        )
                }
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state == .warning
                                     ? Color.orange
                                     : Color.white.opacity(0.85))
            }
        }
    }

    // MARK: Manual IP entry

    private var manualEntrySection: some View {
        VStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    isManualEntryExpanded.toggle()
                }
                if isManualEntryExpanded {
                    // Defer focus so the animation has a beat to start.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        manualFieldFocused = true
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isManualEntryExpanded ? "chevron.up" : "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isManualEntryExpanded ? "Hide manual entry" : "Add device by IP")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)

            if isManualEntryExpanded {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "network")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.55))
                        TextField("", text: $manualHost, prompt: Text("e.g. 192.168.1.42")
                            .foregroundStyle(Color.white.opacity(0.35)))
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(.white)
                            .keyboardType(.numbersAndPunctuation)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($manualFieldFocused)
                            .submitLabel(.go)
                            .onSubmit { submitManualHost() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                    Text("Find your TV's IP under Settings → Network on Roku, or Settings → General → About on Apple TV.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        submitManualHost()
                    } label: {
                        HStack(spacing: 8) {
                            if isProbingManual {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.black)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Text(isProbingManual ? "Connecting…" : "Connect")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isManualHostValid ? Color.white : Color.white.opacity(0.4))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isManualHostValid || isProbingManual)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var isManualHostValid: Bool {
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return false }
        // Accept hostnames OR IPv4 dotted notation; minimal validation so we
        // never block a probe attempt for a typo iOS could still resolve.
        let parts = host.split(separator: ".")
        if parts.count == 4 {
            return parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
        }
        return host.count >= 3
    }

    private func submitManualHost() {
        guard isManualHostValid, !isProbingManual else { return }
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        manualFieldFocused = false
        isProbingManual = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task { @MainActor in
            let ok = await discovery.probeManualHost(host)
            isProbingManual = false
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showToast(ToastState(message: "Added \(host)", icon: "checkmark.circle.fill"))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    isManualEntryExpanded = false
                }
                manualHost = ""
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showToast(ToastState(message: "No TV responded at \(host)", icon: "exclamationmark.triangle.fill"))
            }
        }
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

        // Give the active subnet probe enough time to walk a full /24
        // (~4-6s with 64-host batches) before nudging the user toward the
        // manual entry / Settings fallback.
        permissionCheckTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
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
