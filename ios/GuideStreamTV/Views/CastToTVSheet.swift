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
//  cast.
//

import SwiftUI
import UIKit

struct CastToTVSheet: View {
    @Binding var isPresented: Bool
    let showTitle: String
    let platform: String
    let tmdbId: Int?
    /// `true` for TV series, `false` for movies. Drives the `MediaType`
    /// parameter passed to Roku ECP — channels that accept arbitrary content
    /// IDs (Jellyfin, Plex, sideloaded apps) need the correct type to resolve
    /// the TMDB id to playback.
    var isTV: Bool = true

    @State private var discovery: TVCastDiscovery = TVCastDiscovery()
    @State private var sendingDeviceId: String? = nil
    @State private var toast: ToastState? = nil
    @State private var playingOn: PlayingOnState? = nil
    @State private var limitedModeHelp: LimitedModeHelp? = nil
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
            if let playingOn {
                playingOnBanner(playingOn)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            } else if let toast {
                toastView(toast).padding(.top, 12)
            }
        }
        .sheet(item: $limitedModeHelp) { help in
            LimitedModeHelpSheet(deviceName: help.deviceName)
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
                .scaledFont(size: 20, weight: .bold)
                .foregroundStyle(.white)
            Text(discovery.isScanning && discovery.devices.isEmpty
                 ? "Scanning your network…"
                 : "Choose a device to send \"\(showTitle)\"")
                .scaledFont(size: 13)
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
                    manualEntrySection
                        .padding(.top, 4)
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
                        .scaledFont(size: 30, weight: .regular)
                        .foregroundStyle((showPermissionPrompt || isRunningInSimulator)
                                         ? Color.orange
                                         : Color.white.opacity(0.6))
                        .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                }

                if isRunningInSimulator {
                    Text("Install on your iPhone to cast")
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(.white)
                    Text("This preview runs in a cloud simulator that isn't on your home Wi-Fi, so it can't see your Apple TV or Roku. Install GuideStreamTV on your iPhone via the Rork app and open Play on TV there.")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                } else if phoneOnLinkLocal {
                    Text("Your phone isn't on the Wi-Fi network")
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                    Text("iPhone has a self-assigned address (\(discovery.localIPv4 ?? "169.254.x.x")) because the router didn't give it a real one. Until that's fixed, no app can see your Apple TV or Roku.")
                        .scaledFont(size: 13)
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
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(.white)
                    Text("Connect your iPhone to the same Wi-Fi network as your Apple TV or Roku, then come back and tap Rescan.")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    HStack(spacing: 10) {
                        openWiFiSettingsButton
                        rescanButton
                    }
                } else if showPermissionPrompt {
                    Text("Couldn't find any devices yet")
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(.white)
                    Text("If Local Network access is off, enable it in Settings. Some Wi-Fi networks block device-to-device traffic — you can add your TV by IP below to bypass that.")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    HStack(spacing: 10) {
                        openSettingsButton
                        rescanButton
                    }
                } else {
                    Text("Looking for Apple TV & Roku…")
                        .scaledFont(size: 15)
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text("Make sure your phone and TV are on the same Wi-Fi network.")
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    rescanButton
                }

                if !isRunningInSimulator {
                    manualEntrySection
                        .padding(.top, 6)
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
            .scaledFont(size: 14, weight: .semibold)
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
            .scaledFont(size: 14, weight: .semibold)
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
                .scaledFont(size: 11, weight: .bold, design: .rounded)
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.orange.opacity(0.85)))
            Text(text)
                .scaledFont(size: 12.5)
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
            .scaledFont(size: 14, weight: .semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
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
                        .scaledFont(size: 13, weight: .semibold)
                    Text(isManualEntryExpanded ? "Hide manual entry" : "Add device by IP")
                        .scaledFont(size: 14, weight: .semibold)
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
                            .scaledFont(size: 14)
                            .foregroundStyle(Color.white.opacity(0.55))
                        TextField("", text: $manualHost, prompt: Text("e.g. 192.168.1.42")
                            .foregroundStyle(Color.white.opacity(0.35)))
                            .scaledFont(size: 15, design: .monospaced)
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
                        .scaledFont(size: 11)
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
                                    .scaledFont(size: 14, weight: .semibold)
                            }
                            Text(isProbingManual ? "Connecting…" : "Connect")
                                .scaledFont(size: 14, weight: .semibold)
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
                        .scaledFont(size: 20, weight: .regular)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(device.subtitle)
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                Spacer(minLength: 0)

                if sendingDeviceId == device.id {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 13, weight: .semibold)
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
                .scaledFont(size: 14, weight: .semibold)
            Text(state.message)
                .scaledFont(size: 14, weight: .semibold)
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

    /// Coordinates the full cast-to-TV flow for a selected device:
    ///   1. Dispatch a launch command (Roku ECP for Roku; pending pairing for
    ///      Apple TV — see `dispatchLaunch`).
    ///   2. Register the active session in `CastPlaybackState` so the
    ///      persistent home-screen "Playing on" banner appears.
    ///   3. Show a prominent "Playing on [Device]" banner inside the sheet.
    ///   4. After a beat, open the Roku Remote app (Roku) or dismiss with an
    ///      instructional banner (Apple TV).
    ///   5. Dismiss the sheet.
    ///
    /// Apple TV NEVER triggers an iPhone-side streaming-app deeplink — the
    /// user explicitly flagged that as the wrong behavior. Direct app launch
    /// on Apple TV requires Apple's Companion Link / MediaRemote pairing
    /// (PIN-based handshake, encrypted channel) which is a separate feature.
    /// Until that ships, the banner tells the user to grab their Apple TV
    /// remote and open the app on the TV itself.
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
            let outcome = await dispatchLaunch(for: device)
            await MainActor.run {
                sendingDeviceId = nil

                switch outcome {
                case .ok:
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showPlayingOnBanner(PlayingOnState(
                        deviceName: device.name,
                        deviceKind: device.kind,
                        hint: handoffHint(for: device.kind)
                    ))

                    // Register the session globally so the persistent home
                    // banner takes over after this sheet dismisses. Includes
                    // the host/port for Roku so the home banner's remote-app
                    // button can re-target the same device without re-discovery.
                    CastPlaybackState.shared.start(
                        title: showTitle,
                        platform: platform,
                        deviceName: device.name,
                        deviceKind: device.kind,
                        host: device.host,
                        port: device.port
                    )

                    // Give the user a moment to see the banner, then perform
                    // the follow-up (open remote app or open streaming app
                    // for AirPlay) and dismiss the sheet.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1400))
                        completeHandoff(for: device)
                    }

                case .limitedMode:
                    // The Roku reached us, but it's in Limited Mode and is
                    // rejecting ECP commands from this iPhone. This is the
                    // most common cause of "cast doesn't work" today —
                    // surface the fix path in a dedicated sheet so the user
                    // can flip the setting and try again.
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    limitedModeHelp = LimitedModeHelp(deviceName: device.name)

                case .rejected(let code):
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showToast(ToastState(
                        message: "\(device.name) rejected the request (\(code))",
                        icon: "exclamationmark.triangle.fill"
                    ))

                case .unreachable:
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showToast(ToastState(
                        message: "Couldn't reach \(device.name)",
                        icon: "exclamationmark.triangle.fill"
                    ))
                }
            }
        }
    }

    /// Performs the network-side launch — fires the Roku ECP command, or
    /// returns `.ok` for Apple TV (no network call yet; the user has to open
    /// the app on the TV manually until Companion Link pairing is built).
    private func dispatchLaunch(for device: DiscoveredTVDevice) async -> RokuLaunchResult {
        switch device.kind {
        case .roku:
            guard let host = device.host,
                  let port = device.port,
                  let channelId = RokuChannel.id(for: platform) else {
                return .unreachable
            }
            // Roku ECP is best-effort on the contentId: only channels that
            // explicitly accept arbitrary catalog IDs (sideloaded apps,
            // Jellyfin, Plex) will deep-link straight to playback. For
            // first-party catalogs the TMDB id won't resolve and the channel
            // simply opens to its landing screen — which is the correct
            // graceful fallback.
            return await RokuECPClient.launch(
                host: host,
                port: port,
                channelId: channelId,
                contentId: tmdbId.map { String($0) },
                mediaType: isTV ? "series" : "movie"
            )
        case .appleTV:
            // Apple TV doesn't expose a public deep-link endpoint. The only
            // protocol that can remote-launch a tvOS app is Apple's Companion
            // Link / MediaRemote, which requires a one-time PIN pairing
            // handshake (SRP-6a → Curve25519 → ChaCha20-Poly1305 channel).
            // That's not built yet, so we report success here and let the
            // banner instruct the user. Crucially we DO NOT fall back to
            // opening the streaming app on iPhone — the user explicitly
            // flagged that as incorrect behavior.
            return .ok
        }
    }

    /// Final step in the cast flow — runs after the "Playing on" banner has
    /// been visible long enough for the user to read it.
    ///
    /// Order matters here: we dismiss the sheet BEFORE asking iOS to open
    /// the Roku Remote app. Calling `UIApplication.shared.open` while a
    /// `.sheet` is still presented sometimes loses the app-switch (iOS
    /// queues the foreground request, then drops it when the sheet's
    /// dismiss animation runs first). Dismissing first guarantees the
    /// Roku Remote launch wins the race. `CastPlaybackState.openRokuRemote`
    /// also retries once internally, so a single transient drop won't
    /// silently strand the user without the remote app open.
    private func completeHandoff(for device: DiscoveredTVDevice) {
        switch device.kind {
        case .roku:
            // Tear down the sheet first so iOS hands focus back to the app's
            // main window. Only then ask to open Roku Remote — this way the
            // app-switch animation isn't competing with the sheet dismiss.
            isPresented = false
            Task { @MainActor in
                // Give the sheet's dismiss animation enough time to fully
                // tear down (the default sheet dismissal is ~350ms) before
                // we ask iOS to switch apps. Less than this is what was
                // causing the Roku Remote app to silently not open.
                try? await Task.sleep(for: .milliseconds(450))
                openRemoteApp(for: .roku)
            }
        case .appleTV:
            // No iPhone deeplink. No StreamingDeepLinker. No app switch.
            // The banner stays on screen a beat longer so the user can read
            // the "Open [Platform] on your Apple TV" instruction, then the
            // sheet dismisses cleanly. Once Companion Link pairing ships,
            // this branch will fire the actual remote launch command.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(2400))
                isPresented = false
            }
        }
    }

    /// Contextual one-liner shown under the device name on the banner. Tells
    /// the user what's about to happen so they don't get confused by the
    /// upcoming app switch.
    private func handoffHint(for kind: TVDeviceKind) -> String {
        switch kind {
        case .roku:
            return "Opening Roku Remote…"
        case .appleTV:
            // Apple TV remote-launch needs Companion Link pairing — not
            // built yet. Until then, tell the user exactly what to do.
            return "Open \(platformShortName) on your Apple TV"
        }
    }

    /// Human-friendly platform label for the Apple TV instruction. Keeps the
    /// hint readable when the upstream `platform` string is something verbose
    /// like "HBO Max (subscription)".
    private var platformShortName: String {
        let key = platform.lowercased()
        if key.contains("netflix")              { return "Netflix" }
        if key.contains("hbo") || key.contains("max") { return "Max" }
        if key.contains("hulu")                 { return "Hulu" }
        if key.contains("disney")               { return "Disney+" }
        if key.contains("prime") || key.contains("amazon") { return "Prime Video" }
        if key.contains("apple")                { return "Apple TV+" }
        if key.contains("paramount")            { return "Paramount+" }
        if key.contains("peacock")              { return "Peacock" }
        if key.contains("youtube tv")           { return "YouTube TV" }
        if key.contains("youtube")              { return "YouTube" }
        if key.contains("showtime")             { return "Showtime" }
        if key.contains("starz")                { return "Starz" }
        if key.contains("crunchyroll")          { return "Crunchyroll" }
        return platform
    }

    /// Opens the iOS remote-control app matching the chosen TV. Only Roku
    /// has a maintained iPhone remote (`roku://`); the Apple TV branch in
    /// `completeHandoff` deliberately doesn't call this because the legacy
    /// standalone Apple TV Remote was removed from the App Store in Oct
    /// 2020 and the modern remote lives only in Control Center (no public
    /// URL scheme).
    ///
    /// We delegate to `CastPlaybackState.openRokuRemote()` so the same code
    /// path is reused by the persistent home banner's remote button — a
    /// single source of truth for the Roku launch eliminates duplicate
    /// failure handling.
    private func openRemoteApp(for kind: TVDeviceKind) {
        switch kind {
        case .roku:
            CastPlaybackState.shared.openRokuRemote()
        case .appleTV:
            break
        }
    }

    private func showToast(_ state: ToastState) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = state }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }

    // MARK: Playing-on banner

    /// Visible card shown when a launch succeeds. Lives at the top of the
    /// sheet and supersedes the standard toast — the device handoff is the
    /// most important moment in this flow, so it gets a richer, more
    /// confident visual.
    private struct PlayingOnState: Equatable {
        let deviceName: String
        let deviceKind: TVDeviceKind
        let hint: String
    }

    private func showPlayingOnBanner(_ state: PlayingOnState) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            toast = nil
            playingOn = state
        }
    }

    @ViewBuilder
    private func playingOnBanner(_ state: PlayingOnState) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(state.deviceKind == .appleTV
                          ? Color.white.opacity(0.18)
                          : Color(red: 0x66/255, green: 0x2D/255, blue: 0x91/255).opacity(0.55))
                    .frame(width: 46, height: 46)
                Image(systemName: state.deviceKind == .appleTV ? "appletv" : "tv.inset.filled")
                    .scaledFont(size: 20, weight: .regular)
                    .foregroundStyle(.white)
                // Animated signal arc to communicate "actively casting".
                Image(systemName: "wifi")
                    .scaledFont(size: 11, weight: .bold)
                    .foregroundStyle(Color.green)
                    .padding(4)
                    .background(Circle().fill(Color(red: 0x0A/255, green: 0x10/255, blue: 0x1E/255)))
                    .offset(x: 16, y: -14)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Playing on")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(state.deviceName)
                    .scaledFont(size: 16, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.hint)
                    .scaledFont(size: 11.5)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .scaledFont(size: 24, weight: .regular)
                .foregroundStyle(Color.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Limited Mode help

/// Tag value used to drive the `.sheet(item:)` presentation of the
/// Limited Mode help. Carries the device name so the help copy can be
/// specific ("Living Room Roku rejected the request…").
struct LimitedModeHelp: Identifiable, Equatable {
    let id = UUID()
    let deviceName: String
}

/// Step-by-step fix path for the Roku OS 14.1+ "Network access" default of
/// Limited mode, which blocks the ECP `launch`/`keypress` commands the cast
/// flow depends on. Roku itself surfaces no UI hint when it rejects a
/// command, so the user has no way to know what's wrong unless we tell them.
private struct LimitedModeHelpSheet: View {
    let deviceName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                explanation
                stepsCard
                whyCard
                doneButton
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(Color(red: 0x0A/255, green: 0x10/255, blue: 0x1E/255))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(red: 0x0A/255, green: 0x10/255, blue: 0x1E/255))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundStyle(Color.orange)
                    .padding(8)
                    .background(Circle().fill(Color.orange.opacity(0.18)))
                Text("Roku is in Limited Mode")
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(.white)
            }
            Text("\(deviceName) blocked the launch. A recent Roku update changed the default so phones can't open apps until you enable network control.")
                .scaledFont(size: 14)
                .foregroundStyle(Color.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var explanation: some View {
        Text("Here's the 30-second fix on the Roku itself — you only need to do this once.")
            .scaledFont(size: 13, weight: .semibold)
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepRow(
                number: 1,
                title: "Open Settings on your Roku",
                detail: "Press the Home button on your Roku remote, then scroll down to Settings."
            )
            divider
            stepRow(
                number: 2,
                title: "Go to System → Advanced system settings",
                detail: "Then choose Control by mobile apps → Network access."
            )
            divider
            stepRow(
                number: 3,
                title: "Switch from Limited to Permissive",
                detail: "Or pick Enabled if you want full control from this app. Accept the security prompt that pops up."
            )
            divider
            stepRow(
                number: 4,
                title: "Come back here and try again",
                detail: "Tap the device once more in Play on TV and the channel should open straight away."
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }

    private var whyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .scaledFont(size: 14)
                .foregroundStyle(Color.blue)
            Text("Roku OS 14.1 (December 2024) added a Network access lock that defaults to Limited. Until you change it, every phone and home-automation app gets a 403 from your Roku — not just this one.")
                .scaledFont(size: 12)
                .foregroundStyle(Color.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        )
    }

    private var doneButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } label: {
            Text("Got it")
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                )
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 0.5)
    }

    private func stepRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .scaledFont(size: 13, weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.orange.opacity(0.85))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
