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
import Supabase

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
    var watchmodeSource: WatchmodeSource? = nil
    /// Per-episode Roku ECP launch path from Watchmode's `roku_url` field.
    /// When non-nil, the `.roku` case prefers this over extracting a
    /// contentId from the title-level `webUrl`. Supplied by callers that
    /// resolve episode-level Watchmode sources (e.g. EpisodeDetailSheet).
    var episodeRokuURL: String? = nil

    @State private var discovery: TVCastDiscovery = TVCastDiscovery()
    @State private var sendingDeviceId: String? = nil
    @State private var toast: ToastState? = nil
    @State private var playingOn: PlayingOnState? = nil
    @State private var limitedModeHelp: LimitedModeHelp? = nil
    @State private var rokuLimitedModeDevice: DiscoveredTVDevice? = nil
    @State private var samsungPairingDevice: DiscoveredTVDevice? = nil
    @State private var showPermissionPrompt: Bool = false
    @State private var permissionCheckTask: Task<Void, Never>? = nil
    @State private var isManualEntryExpanded: Bool = false
    @State private var manualHost: String = ""
    @State private var isProbingManual: Bool = false
    @FocusState private var manualFieldFocused: Bool

    var body: some View {
        if rokuLimitedModeDevice != nil {
            rokuLimitedModeView
        } else if samsungPairingDevice != nil {
            samsungPairingView
        } else {
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
                    Text("Looking for Apple TV, Roku, Google TV, Fire TV & Samsung…")
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
            // Open the app's own Settings page — the only officially-supported
            // URL. The private App-Prefs scheme was removed for App Store
            // compliance (it's an undocumented URL that triggers rejection).
            if let appSettingsURL = URL(string: UIApplication.openSettingsURLString) {
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

    /// Opens the app's Settings page so the user can toggle Wi-Fi off/on or
    /// rejoin the network. The private App-Prefs:WIFI scheme was removed for
    /// App Store compliance (undocumented URL that triggers rejection).
    private var openWiFiSettingsButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let appSettingsURL = URL(string: UIApplication.openSettingsURLString) {
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

    // MARK: Device icon helpers

    private func deviceIconName(_ kind: TVDeviceKind) -> String {
        switch kind {
        case .appleTV:     return "appletv"
        case .roku:        return "tv.inset.filled"
        case .googleTV:    return "tv.and.mediabox"
        case .fireTVStick: return "flame.fill"
        case .samsungTV:   return "tv"
        case .lgTV:        return "tv"
        case .macAirPlay:  return "display"
        }
    }

    private func deviceIconBackground(_ kind: TVDeviceKind) -> Color {
        switch kind {
        case .appleTV:     return Color.white.opacity(0.10)
        case .roku:        return Color(red: 0x66/255, green: 0x2D/255, blue: 0x91/255).opacity(0.35)
        case .googleTV:    return Color(red: 0x1A/255, green: 0x73/255, blue: 0xE8/255).opacity(0.35)
        case .fireTVStick: return Color(red: 0xFF/255, green: 0x99/255, blue: 0x00/255).opacity(0.35)
        case .samsungTV:   return Color(red: 0x03/255, green: 0x78/255, blue: 0xFF/255).opacity(0.35)
        case .lgTV:        return Color(red: 0xA5/255, green: 0x00/255, blue: 0x14/255).opacity(0.35)
        case .macAirPlay:  return Color.white.opacity(0.07)
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
                        .fill(deviceIconBackground(device.kind))
                        .frame(width: 46, height: 46)
                    Image(systemName: deviceIconName(device.kind))
                        .scaledFont(size: 20, weight: .regular)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(sendingDeviceId == device.id ? "Connecting…" : device.subtitle)
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                Spacer(minLength: 0)

                if sendingDeviceId == device.id {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(PlaybackSupport.verb(platform: platform, contentURL: nil))
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(Color.white.opacity(0.45))
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

        // For Roku: check ECP is enabled before attempting launch.
        // This avoids burning the Home-keypress + 1.5s sleep on a device
        // that will always 403 due to limited mode.
        if device.kind == .roku {
            Task { @MainActor in
                sendingDeviceId = device.id
                // Resolve host first (handles Bonjour-only devices).
                let resolved = await discovery.resolveHostIfNeeded(for: device)
                guard let host = resolved.host, let port = resolved.port else {
                    sendingDeviceId = nil
                    showToast(ToastState(message: "Couldn't reach \(device.name)", icon: "exclamationmark.triangle.fill"))
                    return
                }
                // Check ECP status before attempting any launch command.
                let ecpStatus = await RokuECPClient.checkECPEnabled(host: host, port: port)
                switch ecpStatus {
                case .limited:
                    sendingDeviceId = nil
                    rokuLimitedModeDevice = device
                    return
                case .unreachable:
                    sendingDeviceId = nil
                    showToast(ToastState(message: "Couldn't reach \(device.name)", icon: "exclamationmark.triangle.fill"))
                    return
                case .enabled:
                    break // proceed to launch
                }
                // ECP confirmed enabled — proceed with normal launch flow.
                let ok = await dispatchLaunch(for: resolved)
                sendingDeviceId = nil
                guard ok else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    let channelKnown = RokuChannel.id(for: platform) != nil
                    let message = channelKnown
                        ? "Roku didn't respond — try again"
                        : "\(platformShortName) not supported on Roku yet"
                    showToast(ToastState(message: message, icon: "exclamationmark.triangle.fill"))
                    return
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showToast(ToastState(
                    message: PlaybackSupport.statusLabel(
                        platform: platform,
                        title: showTitle,
                        room: device.name,
                        contentURL: nil
                    ),
                    icon: "checkmark.circle.fill"
                ))
                showPlayingOnBanner(PlayingOnState(
                    deviceName: device.name,
                    deviceKind: device.kind,
                    hint: handoffHint(for: device.kind)
                ))
                CastPlaybackState.shared.start(
                    title: showTitle,
                    platform: platform,
                    deviceName: device.name,
                    deviceKind: device.kind,
                    host: resolved.host,
                    port: resolved.port
                )
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1400))
                    completeHandoff(for: resolved)
                }
            }
            return
        }

        // Samsung Tizen TV — WebSocket launch with pairing flow.
        if device.kind == .samsungTV {
            Task { @MainActor in
                sendingDeviceId = device.id
                let resolved = await discovery.resolveHostIfNeeded(for: device)
                guard let host = resolved.host else {
                    sendingDeviceId = nil
                    showToast(ToastState(message: "Couldn't reach \(device.name)", icon: "exclamationmark.triangle.fill"))
                    return
                }
                let result = await TizenLaunchClient.launch(host: host, deviceId: device.id, platform: platform)
                sendingDeviceId = nil
                switch result {
                case .ok:
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showToast(ToastState(
                        message: PlaybackSupport.statusLabel(
                            platform: platform,
                            title: showTitle,
                            room: device.name,
                            contentURL: nil
                        ),
                        icon: "checkmark.circle.fill"
                    ))
                    showPlayingOnBanner(PlayingOnState(
                        deviceName: device.name,
                        deviceKind: device.kind,
                        hint: handoffHint(for: device.kind)
                    ))
                    CastPlaybackState.shared.start(
                        title: showTitle,
                        platform: platform,
                        deviceName: device.name,
                        deviceKind: device.kind,
                        host: host,
                        port: device.port
                    )
                case .needsApproval:
                    samsungPairingDevice = device
                case .denied:
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showToast(ToastState(message: "Connection declined on the TV", icon: "exclamationmark.triangle.fill"))
                case .unsupported:
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showToast(ToastState(message: "\(platformShortName) can't be opened on this TV", icon: "exclamationmark.triangle.fill"))
                case .unreachable:
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showToast(ToastState(message: "Couldn't reach \(device.name)", icon: "exclamationmark.triangle.fill"))
                }
            }
            return
        }

        // Non-Roku devices — existing flow unchanged.
        sendingDeviceId = device.id
        Task {
            let ok = await dispatchLaunch(for: device)
            await MainActor.run {
                sendingDeviceId = nil
                guard ok else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showToast(ToastState(message: "Couldn't reach \(device.name)", icon: "exclamationmark.triangle.fill"))
                    return
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showToast(ToastState(
                    message: PlaybackSupport.statusLabel(
                        platform: platform,
                        title: showTitle,
                        room: device.name,
                        contentURL: nil
                    ),
                    icon: "checkmark.circle.fill"
                ))
                showPlayingOnBanner(PlayingOnState(
                    deviceName: device.name,
                    deviceKind: device.kind,
                    hint: handoffHint(for: device.kind)
                ))
                CastPlaybackState.shared.start(
                    title: showTitle,
                    platform: platform,
                    deviceName: device.name,
                    deviceKind: device.kind,
                    host: device.host,
                    port: device.port
                )
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1400))
                    completeHandoff(for: device)
                }
            }
        }
    }

    /// Performs the network-side launch — fires the Roku ECP command, or
    /// returns `true` for Apple TV (no network call yet; the user has to open
    /// the app on the TV manually until Companion Link pairing is built).
    /// Resolves Bonjour-only Roku devices at tap time by scanning the subnet
    /// for a matching device name before attempting ECP.
    private func dispatchLaunch(for device: DiscoveredTVDevice) async -> Bool {
        switch device.kind {
        case .roku:
            let resolved = await discovery.resolveHostIfNeeded(for: device)
            guard let host = resolved.host, let port = resolved.port else {
                #if DEBUG
                print("[CastToTVSheet] Roku launch failed — could not resolve host for '\(device.name)'")
                #endif
                return false
            }
            // Best path: Watchmode's `roku_url` (per-episode or title-level)
            // contains the exact ECP launch path the Roku channel needs.
            let rokuDeepLinkPath: String? = {
                if let ep = episodeRokuURL, !ep.isEmpty, ep.contains("launch/"),
                   !ep.lowercased().contains("deeplinks available"),
                   !ep.lowercased().contains("paid plan") {
                    return ep
                }
                if let ru = watchmodeSource?.rokuUrl, !ru.isEmpty, ru.contains("launch/"),
                   !ru.lowercased().contains("deeplinks available"),
                   !ru.lowercased().contains("paid plan") {
                    return ru
                }
                return nil
            }()
            if let rokuPath = rokuDeepLinkPath {
                #if DEBUG
                print("[CastToTVSheet] Roku Watchmode path → host:\(host) port:\(port) path:\(rokuPath) platform:\(platform)")
                #endif
                let result = await RokuECPClient.launch(host: host, port: port, rokuURLPath: rokuPath)
                return result.isSuccess
            }

            guard let channelId = RokuChannel.id(for: platform) else {
                #if DEBUG
                print("[CastToTVSheet] Roku launch failed — no channel ID for platform '\(platform)'")
                #endif
                _ = await RokuECPClient.keypress(host: host, port: port, key: "Home")
                return false
            }
            // Extract the platform-native content ID from Watchmode's webUrl.
            // On the free Watchmode plan, iosUrl is always a placeholder string
            // ("Deeplinks available for paid plans only.") and cannot be used.
            // webUrl is always a real URL on the free plan and contains the
            // platform's own catalog ID embedded in the path — which is exactly
            // what Roku ECP needs for deep linking.
            let contentId: String? = {
                if let webUrl = watchmodeSource?.webUrl,
                   webUrl.hasPrefix("http"),
                   let id = RokuECPClient.extractContentId(fromWebURL: webUrl, platform: platform),
                   !id.isEmpty {
                    #if DEBUG
                    print("[CastToTVSheet] Roku contentId from webUrl '\(webUrl)': \(id)")
                    #endif
                    return id
                }
                #if DEBUG
                if let webUrl = watchmodeSource?.webUrl {
                    print("[CastToTVSheet] Roku — webUrl '\(webUrl)' yielded no contentId")
                } else {
                    print("[CastToTVSheet] Roku — watchmodeSource is nil, no contentId available")
                }
                #endif
                // TMDB ID fallback — will be ignored by first-party channels but
                // still triggers a plain app open which is the graceful fallback.
                return tmdbId.map { String($0) }
            }()
            #if DEBUG
            print("[CastToTVSheet] Roku launch → host:\(host) port:\(port) channelId:\(channelId) contentId:\(contentId ?? "nil") platform:\(platform)")
            #endif
            let result = await RokuECPClient.launch(
                host: host, port: port, channelId: channelId,
                contentId: contentId,
                mediaType: isTV ? "series" : "movie"
            )
            return result.isSuccess
        case .appleTV:
            // Publish a play command to the tvOS companion app via Supabase
            // realtime. The Apple TV receives it over the play-commands
            // channel and deep-links into the streaming app directly.
            Task {
                await publishPlayCommand(to: device)
            }
            return true
        case .googleTV, .fireTVStick, .samsungTV, .lgTV, .macAirPlay:
            #if DEBUG
            print("[CastToTVSheet] \(device.kind.rawValue) — showing manual instruction banner for '\(device.name)'")
            #endif
            return true
        }
    }

    // MARK: - Supabase play command (Apple TV)

    /// Resolves the title's content URL via Watchmode and broadcasts a
    /// play command to the tvOS companion app over the Supabase realtime
    /// channel `play-commands:{userId}`. The Apple TV picks up the
    /// broadcast, compares `target_name` to `UIDevice.current.name`
    /// (case-insensitive), and deep-links into the streaming app with
    /// `TVOSDeepLinker.open` when there's a match.
    private func publishPlayCommand(to device: DiscoveredTVDevice) async {
        guard let tmdbId else { return }

        let userId = SupabaseManager.shared.client.auth.currentUser?.id.uuidString ?? "guest"
        let resolvedURL = await StreamingDeepLinker.resolveContentURL(
            tmdbId: tmdbId,
            isTV: isTV,
            platform: platform
        )

        // Prefer Watchmode's tvos_url when it is a real native-scheme deep
        // link (hulu://, paramountplus://, nflx://, etc.). The tvOS companion
        // app opens it directly via UIApplication.shared.open, bypassing the
        // per-platform URL reconstruction. Fall back to the resolved web URL
        // when the tvos_url is nil, empty, or a Watchmode placeholder.
        let castURL: String = {
            if let tvos = watchmodeSource?.tvosUrl,
               !tvos.isEmpty,
               tvos.contains("://"),
               !tvos.lowercased().contains("deeplinks available"),
               !tvos.lowercased().contains("paid plan") {
                return tvos
            }
            return resolvedURL?.absoluteString ?? ""
        }()

        let payload = PlayCommandOutgoing(
            platform: platform,
            title: showTitle,
            contentURL: castURL,
            target_name: device.name
        )

        do {
            if let token = try? await SupabaseManager.shared.client.auth.session.accessToken { await SupabaseManager.shared.client.realtimeV2.setAuth(token) }
            let ch = SupabaseManager.shared.client.realtimeV2.channel("play-commands:\(userId)") { config in config.isPrivate = true }
            await ch.subscribe()
            try await ch.broadcast(event: "play-command", message: payload)
            #if DEBUG
            print("[CastToTV] broadcast ok → play-commands:\(userId) target_name=\(device.name) platform=\(platform)")
            #endif
            // Log the outbound command to debug_logs.
            await logPlayCommandSent(device: device, userId: userId, resolvedURL: resolvedURL)
            await ch.unsubscribe()
        } catch {
            #if DEBUG
            print("[CastToTV] broadcast failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Inserts a row into `debug_logs` on every outbound play command so
    /// both sides of the Play on TV flow are traceable.
    private func logPlayCommandSent(device: DiscoveredTVDevice, userId: String, resolvedURL: URL?) async {
        let payloadDict: [String: AnyJSON] = [
            "event": .string("play_command_sent"),
            "user_id": .string(userId),
            "target_name": .string(device.name),
            "device_id": .string(device.id),
            "device_kind": .string(device.kind.rawValue),
            "platform": .string(platform),
            "title": .string(showTitle),
            "content_url": .string(resolvedURL?.absoluteString ?? ""),
            "device_name": .string("STAMP-C tvos=\(watchmodeSource?.tvosUrl ?? "nil") roku=\(watchmodeSource?.rokuUrl ?? "nil")")
        ]
        try? await SupabaseManager.shared.client
            .from("debug_logs")
            .insert(payloadDict)
            .execute()
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
        case .appleTV, .googleTV, .fireTVStick, .samsungTV, .lgTV, .macAirPlay:
            // Show banner long enough to read, then dismiss cleanly.
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
            return "Open \(platformShortName) on your Apple TV"
        case .googleTV:
            return "Open \(platformShortName) on your Google TV"
        case .fireTVStick:
            return "Open \(platformShortName) on your Fire TV"
        case .samsungTV:
            return "Open \(platformShortName) on your Samsung TV"
        case .lgTV:
            return "Use your LG remote to open \(platformShortName)"
        case .macAirPlay:
            return "Open \(platformShortName) on your Mac"
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
        case .appleTV, .googleTV, .fireTVStick, .samsungTV, .lgTV, .macAirPlay:
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
                    .fill(deviceIconBackground(state.deviceKind).opacity(2.0))
                    .frame(width: 46, height: 46)
                Image(systemName: deviceIconName(state.deviceKind))
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

    // MARK: - Roku limited mode inline view

    /// Shown inline (replaces the device list) when the selected Roku is in
    /// limited mode (ECP 403). Mirrors JustWatch's "Device in limited mode"
    /// UX — exact steps, scan again button, and Roku support link.
    @ViewBuilder
    private var rokuLimitedModeView: some View {
        if let device = rokuLimitedModeDevice {
            VStack(spacing: 0) {
                // Device row (non-tappable, shows which device triggered this)
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0x66/255, green: 0x2D/255, blue: 0x91/255).opacity(0.35))
                            .frame(width: 46, height: 46)
                        Image(systemName: "tv.inset.filled")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Roku")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 24)

                Divider().background(Color.white.opacity(0.10))

                // Instructions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Device in limited mode")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)

                    Text("To let GuideStream control your Roku device:")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 12) {
                        rokuLimitedStep(number: "1", text: "Go to your Roku's **Settings → System → Advanced system settings → Control by mobile apps**")
                        rokuLimitedStep(number: "2", text: "Select either **'Enabled'** or **'Permissive'**")
                        rokuLimitedStep(number: "3", text: "Choose **'Yes, allow'** when prompted")
                        rokuLimitedStep(number: "4", text: "Press **Scan again** below")
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 24)

                // Scan again button
                Button {
                    rokuLimitedModeDevice = nil
                    startScan()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                        Text("Scan again")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 0x1A/255, green: 0x6F/255, blue: 0xE8/255))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // Roku support link
                Link("\"Can I use a third-party Roku mobile app?\" - Roku Support",
                     destination: URL(string: "https://support.roku.com/article/360009649793")!)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0x1A/255, green: 0x6F/255, blue: 0xE8/255))
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
            .background(Color(red: 0x0A/255, green: 0x10/255, blue: 0x1E/255))
        }
    }

    // MARK: - Samsung pairing inline view

    /// Shown inline (replaces the device list) when the Samsung TV is waiting
    /// for the user to choose Allow on the TV screen. Mirrors the Roku limited
    /// mode UX with Samsung-specific copy and a Try again button.
    @ViewBuilder
    private var samsungPairingView: some View {
        if let device = samsungPairingDevice {
            VStack(spacing: 0) {
                // Device row (non-tappable, shows which device triggered this)
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0x03/255, green: 0x78/255, blue: 0xFF/255).opacity(0.35))
                            .frame(width: 46, height: 46)
                        Image(systemName: "tv.inset.filled")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Samsung Smart TV")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 24)

                Divider().background(Color.white.opacity(0.10))

                // Instructions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Allow GuideStream on your TV")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)

                    Text("To play on your Samsung TV:")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 12) {
                        rokuLimitedStep(number: "1", text: "A connection request from GuideStream should appear on your TV — choose **Allow**")
                        rokuLimitedStep(number: "2", text: "If you don't see it, make sure the TV is on and on the same Wi-Fi network")
                        rokuLimitedStep(number: "3", text: "On newer Samsung TVs, set **Device Connection Manager → Access Notification** to **First Time Only** so it won't ask again")
                        rokuLimitedStep(number: "4", text: "Tap **Try again** below")
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 24)

                // Try again button
                Button {
                    samsungPairingDevice = nil
                    handleSelect(device)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try again")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 0x1A/255, green: 0x6F/255, blue: 0xE8/255))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
            .background(Color(red: 0x0A/255, green: 0x10/255, blue: 0x1E/255))
        }
    }

    private func rokuLimitedStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number + ".")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 20, alignment: .leading)
            Text(parseLimitedModeBold(text))
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Converts **text** markdown-style bold markers to an AttributedString.
    private func parseLimitedModeBold(_ input: String) -> AttributedString {
        var result = AttributedString()
        var remaining = input
        while let openRange = remaining.range(of: "**") {
            let before = String(remaining[remaining.startIndex..<openRange.lowerBound])
            result += AttributedString(before)
            remaining = String(remaining[openRange.upperBound...])
            if let closeRange = remaining.range(of: "**") {
                var bold = AttributedString(String(remaining[remaining.startIndex..<closeRange.lowerBound]))
                bold.font = .system(size: 15, weight: .semibold)
                result += bold
                remaining = String(remaining[closeRange.upperBound...])
            }
        }
        result += AttributedString(remaining)
        return result
    }
}

// MARK: - Play command payload (Supabase realtime)

/// Encodable payload broadcast to the `play-commands:{userId}` realtime
/// channel so the tvOS companion can pick it up and deep-link. The tvOS
/// app matches `target_name` against `UIDevice.current.name` so the same
/// Bonjour-discovered name must appear on both sides.
nonisolated struct PlayCommandOutgoing: Codable, Sendable {
    let platform: String
    let title: String
    let contentURL: String
    let target_name: String
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
