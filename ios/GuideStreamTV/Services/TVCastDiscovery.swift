//
//  TVCastDiscovery.swift
//  GuideStreamTV
//
//  Scans the local network for Apple TV (Bonjour/AirPlay) and Roku devices.
//
//  Discovery uses three concurrent strategies:
//    1. Bonjour browsers for AirPlay/RAOP/companion-link (Apple TV) and _rsp
//       (some Rokus). Requires NSBonjourServices in Info.plist.
//    2. Active subnet probe of every host on the local /24, hitting Roku ECP
//       on :8060 and AirPlay /info on :7000. Uses raw NWConnection sockets
//       because URLSession is blocked by App Transport Security for cleartext
//       requests to LAN IP literals.
//    3. Manual host probe (entered by the user) — same probe pipeline as the
//       subnet scan but for a single explicit IP. Lets users get unblocked when
//       AP isolation, VPN, or IGMP snooping prevent auto-discovery.
//
//  The class publishes live diagnostic state so the UI can show what the scan
//  actually saw — local IP, hosts scanned vs total, and how many Bonjour
//  endpoints were observed. If those numbers stay at zero, the user can tell
//  at a glance whether LAN access, network routing, or device responses are
//  the problem.
//

import Foundation
import Network
import Observation
import Darwin

enum TVDeviceKind: String {
    case appleTV
    case roku
    case googleTV    // Chromecast / Google TV stick or built-in
    case fireTVStick // Amazon Fire TV stick or cube
    case samsungTV  // Samsung Tizen Smart TV
    case lgTV        // LG webOS TV with AirPlay 2 built-in
    case macAirPlay  // Mac AirPlay receiver — shown in list but not launchable
}

struct DiscoveredTVDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: TVDeviceKind
    let host: String?
    let port: UInt16?

    var subtitle: String {
        switch kind {
        case .appleTV:     return "Apple TV"
        case .roku:        return "Roku"
        case .googleTV:    return "Google TV / Chromecast"
        case .fireTVStick: return "Amazon Fire TV"
        case .samsungTV:   return "Samsung Smart TV"
        case .lgTV:        return "LG Smart TV"
        case .macAirPlay:  return "Mac — AirPlay"
        }
    }
}

@MainActor
@Observable
final class TVCastDiscovery {
    private(set) var devices: [DiscoveredTVDevice] = []
    private(set) var isScanning: Bool = false

    // Diagnostics surfaced to the UI so the user (and us) can see what the
    // scan actually saw, instead of an opaque empty list.
    private(set) var localIPv4: String? = nil
    private(set) var scannedHosts: Int = 0
    private(set) var totalHosts: Int = 0
    private(set) var bonjourEndpointsSeen: Int = 0

    @ObservationIgnored private var browsers: [NWBrowser] = []
    @ObservationIgnored private var permissionPokeListener: NWListener?
    @ObservationIgnored private var subnetScanTask: Task<Void, Never>?

    func start() {
        guard !isScanning else { return }
        isScanning = true
        devices = []
        localIPv4 = nil
        scannedHosts = 0
        totalHosts = 0
        bonjourEndpointsSeen = 0
        TVCastDiscoveryStore.register(self)

        // Force iOS to surface the Local Network permission prompt and
        // register the app on the LAN.
        startPermissionPokeListener()

        // Apple TV / AirPlay receivers via Bonjour.
        browseBonjour(type: "_airplay._tcp", kind: .appleTV)
        browseBonjour(type: "_raop._tcp",    kind: .appleTV)
        browseBonjour(type: "_companion-link._tcp", kind: .appleTV)
        // Some Roku models advertise _rsp._tcp.
        browseBonjour(type: "_rsp._tcp", kind: .roku)

        // Google TV / Chromecast — reliable mDNS advertisement on all models.
        browseBonjour(type: "_googlecast._tcp", kind: .googleTV)

        // Amazon Fire TV — advertises via mDNS on the local network.
        browseBonjour(type: "_amzn-wplay._tcp", kind: .fireTVStick)

        // Active subnet probe — the reliable path for Roku and a great
        // Bonjour fallback for Apple TV.
        startSubnetProbe()

        // Samsung Tizen TVs use SSDP (UDP multicast) not Bonjour.
        startSSDPProbe()
    }

    func stop() {
        isScanning = false
        for b in browsers { b.cancel() }
        browsers = []
        permissionPokeListener?.cancel()
        permissionPokeListener = nil
        subnetScanTask?.cancel()
        subnetScanTask = nil
    }

    /// Probes a user-entered IP for Roku ECP (:8060) or AirPlay (:7000) and
    /// adds the device to the list if either responds. Returns `true` if a
    /// device was added. Used as a fallback when auto-discovery fails (AP
    /// isolation, VPN routing, weird subnet masks, etc.).
    func probeManualHost(_ rawHost: String) async -> Bool {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return false }

        // Roku ECP on :8060.
        if let rokuInfo = await Self.rawHTTPGet(host: host, port: 8060, path: "/query/device-info", timeout: 3.0),
           rokuInfo.lowercased().contains("roku") {
            let name = Self.extractTag("user-device-name", from: rokuInfo)
                ?? Self.extractTag("friendly-device-name", from: rokuInfo)
                ?? Self.extractTag("model-name", from: rokuInfo)
                ?? "Roku (\(host))"
            let udn = Self.extractTag("device-id", from: rokuInfo) ?? host
            mergeFound([(id: "roku-\(udn)", name: name, host: host, port: 8060)], kind: .roku)
            return true
        }

        // AirPlay on :7000 — covers Apple TV, LG webOS TVs, and Macs.
        // The classifier reads the model field from the plist to distinguish them.
        if let airplayData = await Self.rawHTTPGetData(host: host, port: 7000, path: "/info", timeout: 3.0),
           Self.isAirPlayResponse(airplayData) {
            let name = Self.extractAirPlayName(from: airplayData) ?? "AirPlay Device (\(host))"
            let deviceID = Self.extractAirPlayDeviceID(from: airplayData) ?? host
            let kind = Self.classifyAirPlayDevice(from: airplayData, name: name)

            // Filter out Macs entirely — they are not TVs.
            guard kind != .macAirPlay else {
                #if DEBUG
                print("[TVCastDiscovery] skipping Mac AirPlay receiver '\(name)' @ \(host)")
                #endif
                return false
            }

            let idPrefix = kind == .lgTV ? "lgtv" : "appletv"
            mergeFound([(id: "\(idPrefix)-\(deviceID)", name: name, host: host, port: 7000)], kind: kind)
            return true
        }

        return false
    }

    /// If `device.host` is nil (Bonjour-only discovery), scans the subnet
    /// to find the Roku by name and returns an updated device with host+port.
    /// Returns the original device unchanged if resolution fails or host is already set.
    func resolveHostIfNeeded(for device: DiscoveredTVDevice) async -> DiscoveredTVDevice {
        if device.host != nil, device.port != nil { return device }
        guard device.kind == .roku else { return device }
        if let resolved = await Self.resolveRokuByName(device.name) {
            mergeFound(
                [(id: resolved.id, name: resolved.name, host: resolved.host, port: resolved.port)],
                kind: .roku
            )
            return resolved
        }
        return device
    }

    nonisolated private static func resolveRokuByName(_ targetName: String) async -> DiscoveredTVDevice? {
        guard let localIP = localIPv4Address() else { return nil }
        let parts = localIP.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let prefix = "\(parts[0]).\(parts[1]).\(parts[2])."
        let allHosts = (1...254).map { "\(prefix)\($0)" }
        let batchSize = 64
        var index = 0
        while index < allHosts.count {
            let end = min(index + batchSize, allHosts.count)
            let batch = Array(allHosts[index..<end])
            let result: DiscoveredTVDevice? = await withTaskGroup(of: DiscoveredTVDevice?.self) { group in
                for host in batch {
                    group.addTask {
                        guard let info = await rawHTTPGet(host: host, port: 8060, path: "/query/device-info", timeout: 1.0),
                              info.lowercased().contains("roku") else { return nil }
                        let name = extractTag("user-device-name", from: info)
                            ?? extractTag("friendly-device-name", from: info)
                            ?? extractTag("model-name", from: info)
                            ?? "Roku (\(host))"
                        guard name.trimmingCharacters(in: .whitespaces).lowercased()
                            == targetName.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
                        let udn = extractTag("device-id", from: info) ?? host
                        return DiscoveredTVDevice(id: "roku-\(udn)", name: name, kind: .roku, host: host, port: 8060)
                    }
                }
                for await r in group { if let r { return r } }
                return nil
            }
            if let found = result { return found }
            index = end
        }
        return nil
    }

    // MARK: - Permission poke

    private func startPermissionPokeListener() {
        guard permissionPokeListener == nil else { return }
        let listener = try? NWListener(using: .udp)
        listener?.service = NWListener.Service(name: "GuideStreamTVDiscovery", type: "_guidestreamtv._udp")
        listener?.newConnectionHandler = { c in c.cancel() }
        listener?.start(queue: .main)
        permissionPokeListener = listener
    }

    // MARK: - Bonjour (Apple TV)

    private func browseBonjour(type: String, kind: TVDeviceKind) {
        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: params)
        let kindString = kind.rawValue
        browser.stateUpdateHandler = { state in
            #if DEBUG
            print("[TVCastDiscovery] \(type) browser state: \(state)")
            #endif
        }
        browser.browseResultsChangedHandler = { results, _ in
            var found: [(id: String, name: String, host: String?, port: UInt16?)] = []
            for result in results {
                if case let .service(name, _, _, _) = result.endpoint {
                    // Filter out obvious Mac AirPlay receivers by name at Bonjour time.
                    // Full classification happens later in the subnet probe when we have
                    // the actual plist data.
                    let lower = name.lowercased()
                    let looksLikeMac = lower.contains("macbook") || lower.contains("imac")
                        || lower.contains("mac mini") || lower.contains("mac pro")
                        || lower.contains("'s macbook") || lower.contains("s macbook")
                    if looksLikeMac { continue }
                    found.append((id: "\(kindString)-\(name)", name: name, host: nil, port: nil))
                }
            }
            let snapshot = found
            let endpointCount = results.count
            Task { @MainActor in
                TVCastDiscoveryStore.recordBonjourEndpoints(endpointCount)
                TVCastDiscoveryStore.merge(snapshot: snapshot, kind: kind)
            }
        }
        browser.start(queue: .main)
        browsers.append(browser)
    }

    // MARK: - Subnet probe (Roku ECP + AirPlay fallback)

    private func startSubnetProbe() {
        subnetScanTask?.cancel()
        subnetScanTask = Task.detached(priority: .userInitiated) {
            guard let localIP = Self.localIPv4Address() else {
                #if DEBUG
                print("[TVCastDiscovery] no local IPv4 — skipping subnet probe")
                #endif
                return
            }
            await MainActor.run {
                TVCastDiscoveryStore.setLocalIPv4(localIP)
            }
            let parts = localIP.split(separator: ".")
            guard parts.count == 4 else { return }
            let prefix = "\(parts[0]).\(parts[1]).\(parts[2])."
            #if DEBUG
            print("[TVCastDiscovery] probing subnet \(prefix)0/24")
            #endif

            let allHosts = (1...254).map { "\(prefix)\($0)" }
            await MainActor.run {
                TVCastDiscoveryStore.setTotalHosts(allHosts.count)
            }

            // Probe in larger batches for faster completion (~4s end-to-end
            // versus ~12s with batches of 32). 64 parallel TCP connects is
            // well within the iOS socket budget.
            let batchSize = 64
            var index = 0
            while index < allHosts.count {
                if Task.isCancelled { return }
                let end = min(index + batchSize, allHosts.count)
                await withTaskGroup(of: Void.self) { group in
                    for host in allHosts[index..<end] {
                        group.addTask {
                            await Self.probe(host: host)
                            await MainActor.run {
                                TVCastDiscoveryStore.incrementScannedHosts()
                            }
                        }
                    }
                }
                index = end
            }
        }
    }

    // MARK: - SSDP probe (Samsung Tizen)

    /// Sends a UPnP/SSDP M-SEARCH multicast packet to 239.255.255.255:1900.
    /// Samsung Smart TVs (Tizen) respond with their USN and SERVER headers,
    /// letting us detect them without walking the full /24.
    /// Uses NWConnection with UDP so ATS cleartext rules don't apply.
    private func startSSDPProbe() {
        Task.detached(priority: .userInitiated) {
            let message =
                "M-SEARCH * HTTP/1.1\r\n" +
                "HOST: 239.255.255.255:1900\r\n" +
                "MAN: \"ssdp:discover\"\r\n" +
                "MX: 3\r\n" +
                "ST: urn:samsung.com:device:RemoteControlReceiver:1\r\n\r\n"

            guard let data = message.data(using: .utf8) else { return }

            // Send to SSDP multicast address.
            let host = NWEndpoint.Host("239.255.255.255")
            guard let port = NWEndpoint.Port(rawValue: 1900) else { return }
            let params = NWParameters.udp
            params.prohibitedInterfaceTypes = [.cellular]
            let conn = NWConnection(host: host, port: port, using: params)

            conn.stateUpdateHandler = { state in
                if state == .ready {
                    conn.send(content: data, completion: .contentProcessed { _ in })
                    // Listen for responses for 4 seconds.
                    Self.receiveSSDPResponses(conn: conn, duration: 4.0)
                }
            }
            conn.start(queue: .global(qos: .userInitiated))

            // Cancel after 5 seconds total.
            try? await Task.sleep(for: .seconds(5))
            conn.cancel()
        }
    }

    nonisolated private static func receiveSSDPResponses(conn: NWConnection, duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        func readNext() {
            guard Date() < deadline else { conn.cancel(); return }
            conn.receiveMessage { data, _, _, error in
                if let data = data,
                   let response = String(data: data, encoding: .utf8) {
                    let lower = response.lowercased()
                    // Samsung Tizen TVs include "samsung" and "tizen" or
                    // "RemoteControlReceiver" in their SSDP response.
                    if lower.contains("samsung") || lower.contains("tizen") ||
                        lower.contains("remotecontrolreceiver") {
                        // Extract USN as stable ID, LOCATION for IP.
                        let usn = Self.ssdpHeaderValue("USN", from: response) ?? UUID().uuidString
                        let location = Self.ssdpHeaderValue("LOCATION", from: response) ?? ""
                        let friendlyName = Self.ssdpHeaderValue("SERVER", from: response) ?? "Samsung TV"
                        // Pull IP from LOCATION URL, e.g. http://192.168.1.5:52235/...
                        let host = Self.extractHostFromURL(location)
                        let snapshot: [(id: String, name: String, host: String?, port: UInt16?)] =
                            [(id: "samsung-\(usn)", name: friendlyName, host: host, port: 8001)]
                        Task { @MainActor in
                            TVCastDiscoveryStore.merge(snapshot: snapshot, kind: .samsungTV)
                        }
                    }
                }
                if error == nil { readNext() }
            }
        }
        readNext()
    }

    nonisolated private static func ssdpHeaderValue(_ header: String, from response: String) -> String? {
        let lines = response.components(separatedBy: "\r\n")
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == header.lowercased() {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    nonisolated private static func extractHostFromURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        return host
    }

    nonisolated private static func probe(host: String) async {
        // Roku ECP on :8060 — XML device-info; cheap and reliable.
        if let rokuInfo = await rawHTTPGet(host: host, port: 8060, path: "/query/device-info", timeout: 1.0),
           rokuInfo.lowercased().contains("roku") {
            let name = extractTag("user-device-name", from: rokuInfo)
                ?? extractTag("friendly-device-name", from: rokuInfo)
                ?? extractTag("model-name", from: rokuInfo)
                ?? "Roku (\(host))"
            let udn = extractTag("device-id", from: rokuInfo) ?? host
            let snapshot: [(id: String, name: String, host: String?, port: UInt16?)] =
                [(id: "roku-\(udn)", name: name, host: host, port: 8060)]
            #if DEBUG
            print("[TVCastDiscovery] found Roku \(name) @ \(host)")
            #endif
            await MainActor.run {
                TVCastDiscoveryStore.merge(snapshot: snapshot, kind: .roku)
            }
            return
        }

        // AirPlay on :7000 — covers Apple TV, LG webOS TVs, and Macs.
        // The classifier reads the model field from the plist to distinguish them.
        if let airplayData = await rawHTTPGetData(host: host, port: 7000, path: "/info", timeout: 1.5),
           isAirPlayResponse(airplayData) {
            let name = extractAirPlayName(from: airplayData) ?? "AirPlay Device (\(host))"
            let deviceID = extractAirPlayDeviceID(from: airplayData) ?? host
            let kind = classifyAirPlayDevice(from: airplayData, name: name)

            // Filter out Macs entirely — they are not TVs.
            guard kind != .macAirPlay else {
                #if DEBUG
                print("[TVCastDiscovery] skipping Mac AirPlay receiver '\(name)' @ \(host)")
                #endif
                return
            }

            let idPrefix = kind == .lgTV ? "lgtv" : "appletv"
            let snapshot: [(id: String, name: String, host: String?, port: UInt16?)] =
                [(id: "\(idPrefix)-\(deviceID)", name: name, host: host, port: 7000)]
            #if DEBUG
            print("[TVCastDiscovery] found \(kind.rawValue) '\(name)' @ \(host)")
            #endif
            await MainActor.run {
                TVCastDiscoveryStore.merge(snapshot: snapshot, kind: kind)
            }
            return
        }

        // Google TV / Chromecast REST API on :8008.
        if let googleResponse = await rawHTTPGet(host: host, port: 8008, path: "/setup/eureka_info", timeout: 1.0),
           !googleResponse.isEmpty {
            let lower = googleResponse.lowercased()
            if lower.contains("chromecast") || lower.contains("google") || lower.contains("eureka") {
                // Extract name from JSON "name" field — simple scan, no full parser needed.
                let name = jsonStringValue("name", from: googleResponse)
                    ?? jsonStringValue("friendly_name", from: googleResponse)
                    ?? "Chromecast (\(host))"
                let deviceId = jsonStringValue("ssdp_udn", from: googleResponse) ?? host
                let snapshot: [(id: String, name: String, host: String?, port: UInt16?)] =
                    [(id: "googletv-\(deviceId)", name: name, host: host, port: 8008)]
                #if DEBUG
                print("[TVCastDiscovery] found Google TV \(name) @ \(host)")
                #endif
                await MainActor.run {
                    TVCastDiscoveryStore.merge(snapshot: snapshot, kind: .googleTV)
                }
                return
            }
        }

        // Samsung Tizen REST API on :8001.
        if let samsungResponse = await rawHTTPGet(host: host, port: 8001, path: "/api/v2/", timeout: 1.0),
           !samsungResponse.isEmpty {
            let lower = samsungResponse.lowercased()
            if lower.contains("samsung") || lower.contains("tizen") {
                let name = jsonStringValue("name", from: samsungResponse)
                    ?? jsonStringValue("DeviceName", from: samsungResponse)
                    ?? "Samsung TV (\(host))"
                let udn = jsonStringValue("id", from: samsungResponse) ?? host
                let snapshot: [(id: String, name: String, host: String?, port: UInt16?)] =
                    [(id: "samsung-\(udn)", name: name, host: host, port: 8001)]
                #if DEBUG
                print("[TVCastDiscovery] found Samsung TV \(name) @ \(host)")
                #endif
                await MainActor.run {
                    TVCastDiscoveryStore.merge(snapshot: snapshot, kind: .samsungTV)
                }
                return
            }
        }
    }

    /// Returns `true` if the response body looks like an AirPlay `/info`
    /// payload. Modern tvOS returns a binary plist (`bplist00` magic);
    /// some older receivers return XML or text. Port 7000 is reserved for
    /// AirPlay so any meaningful HTTP response on that port is treated as
    /// a positive match.
    nonisolated private static func isAirPlayResponse(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        // Binary plist magic — definitive AirPlay signature on modern Apple TV.
        if data.count >= 8 {
            let magic: [UInt8] = [0x62, 0x70, 0x6c, 0x69, 0x73, 0x74, 0x30, 0x30] // "bplist00"
            var matchesMagic = true
            for i in 0..<8 where data[i] != magic[i] { matchesMagic = false; break }
            if matchesMagic { return true }
        }
        // XML / text response — legacy receivers.
        if let body = String(data: data, encoding: .utf8) {
            let lower = body.lowercased()
            if lower.contains("airplay")
                || lower.contains("appletv")
                || lower.contains("apple tv")
                || lower.contains("deviceid")
                || lower.contains("model") {
                return true
            }
        }
        // Last-resort: port 7000 is reserved for AirPlay, so any substantive
        // response (not a stray RST packet) is overwhelmingly likely to be
        // an Apple TV. We require >= 50 bytes to avoid noise.
        return data.count >= 50
    }

    /// Pulls the receiver's display name out of an AirPlay `/info` body.
    /// Tries binary plist parsing first (modern tvOS), then XML/text, then
    /// a byte-scan heuristic on the binary form as a final fallback.
    nonisolated private static func extractAirPlayName(from data: Data) -> String? {
        // Modern tvOS: binary plist.
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            if let n = plist["name"] as? String, !n.isEmpty { return n }
            if let n = plist["deviceName"] as? String, !n.isEmpty { return n }
            if let n = plist["model"] as? String, !n.isEmpty { return n }
        }
        // Legacy / XML.
        if let body = String(data: data, encoding: .utf8) {
            if let n = plistStringValue(key: "name", in: body) { return n }
            if let n = plistStringValue(key: "deviceName", in: body) { return n }
        }
        // Heuristic byte-scan — binary plists store ASCII keys & values inline.
        if let n = scanBinaryForStringAfter(key: "name", in: data) { return n }
        if let n = scanBinaryForStringAfter(key: "deviceName", in: data) { return n }
        return nil
    }

    /// Pulls a stable per-device identifier (MAC-style `deviceid` or `pi`
    /// UUID) so the same Apple TV gets the same row across rescans.
    nonisolated private static func extractAirPlayDeviceID(from data: Data) -> String? {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            if let id = plist["deviceid"] as? String, !id.isEmpty { return id }
            if let id = plist["pi"] as? String, !id.isEmpty { return id }
        }
        return nil
    }

    /// Classifies an AirPlay `/info` response into the correct TVDeviceKind.
    /// Apple TV, LG webOS TVs, and Macs all respond on port 7000 — the `model`
    /// field in the plist is the only reliable differentiator.
    ///
    /// Apple TV models: AppleTV5,3 / AppleTV6,2 / AppleTV11,1 / AppleTV14,1
    /// LG AirPlay models: contain "LG" in the model or name field, or report
    /// manufacturer "LG Electronics"
    /// Mac models: MacBookPro / MacBookAir / Macmini / MacPro / iMac
    nonisolated private static func classifyAirPlayDevice(from data: Data, name: String) -> TVDeviceKind {
        var model: String = ""
        var manufacturer: String = ""

        // Binary plist — most reliable source.
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            model = (plist["model"] as? String ?? "").lowercased()
            manufacturer = (plist["manufacturer"] as? String ?? "").lowercased()
        }

        // XML / text fallback.
        if model.isEmpty, let body = String(data: data, encoding: .utf8) {
            model = (plistStringValue(key: "model", in: body) ?? "").lowercased()
            manufacturer = (plistStringValue(key: "manufacturer", in: body) ?? "").lowercased()
        }

        let nameLower = name.lowercased()

        // Mac: model starts with known Mac prefixes.
        let macPrefixes = ["macbookpro", "macbookair", "macmini", "macpro", "imac", "mac14", "mac13"]
        if macPrefixes.contains(where: { model.hasPrefix($0) }) { return .macAirPlay }

        // LG: manufacturer field, model contains "lg", or name contains "[LG]" or "webos".
        if manufacturer.contains("lg")
            || model.hasPrefix("lg")
            || nameLower.contains("[lg]")
            || nameLower.contains("webos")
            || nameLower.contains("oled")
            || nameLower.contains("nanocell") { return .lgTV }

        // Apple TV: model starts with "AppleTV" prefix.
        if model.hasPrefix("appletv") { return .appleTV }

        // Fallback: if the name contains obvious Mac indicators.
        if nameLower.contains("macbook") || nameLower.contains("imac") || nameLower.contains("mac mini") { return .macAirPlay }

        // Default: treat unknown AirPlay receivers as Apple TV (safe fallback).
        return .appleTV
    }

    /// Best-effort scan for a string value immediately following an ASCII
    /// key inside a binary plist. Binary plist stores short ASCII strings
    /// inline with a one-byte type marker (`0x5X` where `X` is length 1-14),
    /// so once we find the key bytes we can usually read the next value
    /// without a full parser. Used only when `PropertyListSerialization`
    /// fails (truncated or oddly-encoded responses).
    nonisolated private static func scanBinaryForStringAfter(key: String, in data: Data) -> String? {
        let keyBytes = Array(key.utf8)
        guard data.count > keyBytes.count + 2 else { return nil }
        let lastSearchIndex = data.count - keyBytes.count
        var i = 0
        while i < lastSearchIndex {
            var match = true
            for j in 0..<keyBytes.count where data[i + j] != keyBytes[j] { match = false; break }
            if match {
                // Scan forward up to 64 bytes for an inline ASCII string
                // marker (0x51...0x5E = ASCII string of length 1-14).
                let scanEnd = min(i + keyBytes.count + 64, data.count - 1)
                var k = i + keyBytes.count
                while k < scanEnd {
                    let b = data[k]
                    if b >= 0x51 && b <= 0x5E {
                        let length = Int(b - 0x50)
                        if k + 1 + length <= data.count {
                            let slice = data.subdata(in: (k + 1)..<(k + 1 + length))
                            if let s = String(data: slice, encoding: .utf8),
                               !s.isEmpty,
                               s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) {
                                return s.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }
                    k += 1
                }
            }
            i += 1
        }
        return nil
    }

    /// Performs an HTTP/1.0 GET via raw NWConnection so ATS doesn't block
    /// cleartext requests to LAN IP literals. Returns the body as a UTF-8
    /// string — only suitable for endpoints that respond with text (e.g.
    /// Roku ECP XML). For endpoints that may return binary data (AirPlay
    /// `/info` on modern Apple TV returns a binary plist), use
    /// `rawHTTPGetData` instead so the bytes aren't lost during string
    /// conversion.
    nonisolated private static func rawHTTPGet(host: String, port: UInt16, path: String, timeout: TimeInterval) async -> String? {
        guard let data = await rawHTTPGetData(host: host, port: port, path: path, timeout: timeout) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Same wire protocol as `rawHTTPGet` but returns the raw response body
    /// bytes (with HTTP headers stripped at the byte level). Necessary for
    /// endpoints that return binary plists or other non-UTF8 payloads —
    /// `String(data:encoding:.utf8)` returns nil on invalid sequences, so
    /// converting to String first would silently discard the entire response.
    nonisolated private static func rawHTTPGetData(host: String, port: UInt16, path: String, timeout: TimeInterval) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: nil); return
            }
            let params = NWParameters.tcp
            params.prohibitedInterfaceTypes = [.cellular]
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)

            let lock = NSLock()
            var didResume = false
            let finish: (Data?) -> Void = { value in
                lock.lock()
                let already = didResume
                didResume = true
                lock.unlock()
                if already { return }
                conn.cancel()
                continuation.resume(returning: value)
            }

            // Hard timeout.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // The User-Agent matters for some Apple TV firmware —
                    // mimicking AirPlay's own client UA gets a richer
                    // /info response than a generic one.
                    let req = "GET \(path) HTTP/1.0\r\nHost: \(host)\r\nUser-Agent: AirPlay/540.31\r\nConnection: close\r\nAccept: */*\r\n\r\n"
                    conn.send(content: req.data(using: .utf8), completion: .contentProcessed { _ in })
                    var buffer = Data()
                    func readNext() {
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
                            if let data = data, !data.isEmpty { buffer.append(data) }
                            if isComplete || error != nil || buffer.count > 64 * 1024 {
                                if let bodyStart = findHTTPBodyStart(in: buffer) {
                                    finish(buffer.subdata(in: bodyStart..<buffer.count))
                                } else {
                                    finish(buffer.isEmpty ? nil : buffer)
                                }
                                return
                            }
                            readNext()
                        }
                    }
                    readNext()
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Locates the start of the HTTP body (the byte immediately after the
    /// first `\r\n\r\n` separator) without touching string encoding.
    /// Returns `nil` if no separator is present in the buffer.
    nonisolated private static func findHTTPBodyStart(in data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        let needle: [UInt8] = [0x0d, 0x0a, 0x0d, 0x0a] // \r\n\r\n
        var i = 0
        let upper = data.count - 4
        while i <= upper {
            if data[i] == needle[0]
                && data[i + 1] == needle[1]
                && data[i + 2] == needle[2]
                && data[i + 3] == needle[3] {
                return i + 4
            }
            i += 1
        }
        return nil
    }

    /// Extracts a string value for a given key from a minimal JSON response
    /// without importing Foundation's JSONSerialization — avoids the overhead
    /// for the simple flat objects returned by Chromecast and Samsung REST APIs.
    nonisolated private static func jsonStringValue(_ key: String, from json: String) -> String? {
        // Matches: "key":"value" or "key": "value"
        let pattern = "\"\(key)\"\\s*:\\s*\"([^\"]+)\""
        guard let range = json.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(json[range])
        // Extract the captured value between the last pair of quotes.
        let parts = match.components(separatedBy: "\"")
        return parts.count >= 4 ? parts[parts.count - 2] : nil
    }

    nonisolated private static func extractTag(_ tag: String, from xml: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let s = xml.range(of: open),
              let e = xml.range(of: close, range: s.upperBound..<xml.endIndex) else { return nil }
        return String(xml[s.upperBound..<e.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func plistStringValue(key: String, in plist: String) -> String? {
        // <key>name</key><string>Living Room</string>
        guard let keyRange = plist.range(of: "<key>\(key)</key>", options: .caseInsensitive) else { return nil }
        let after = plist[keyRange.upperBound...]
        guard let s = after.range(of: "<string>"),
              let e = after.range(of: "</string>", range: s.upperBound..<after.endIndex) else { return nil }
        return String(after[s.upperBound..<e.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Local IPv4 discovery

    /// Returns the device's primary Wi-Fi IPv4 address (e.g. "192.168.1.42").
    ///
    /// iOS routinely exposes more than one IPv4 address on `en0` — for
    /// example a real DHCP-assigned address (192.168.x.x) alongside a
    /// leftover link-local (169.254.x.x) that the OS keeps as a fallback.
    /// The previous implementation took the first match it saw, which
    /// sometimes was the link-local — making the subnet scan walk a dead
    /// /24 even though the phone was actually on the LAN. Here we collect
    /// every candidate and rank them, preferring en0 + RFC1918 private
    /// space first.
    nonisolated private static func localIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        struct Candidate { let name: String; let ip: String }
        var candidates: [Candidate] = []

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }

            let flags = Int32(cur.pointee.ifa_flags)
            guard let addrPtr = cur.pointee.ifa_addr else { continue }
            let addr = addrPtr.pointee
            guard (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
                  addr.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: cur.pointee.ifa_name)
            // Skip non-LAN interfaces. The real Wi-Fi LAN is en0 (sometimes
            // en1/en2 on iPad). Everything else here is a peer-to-peer or
            // tunneled interface that can't see the home Wi-Fi.
            //   awdl/llw   = Apple Wireless Direct Link / Low Latency Wi-Fi
            //   utun/ipsec = VPN tunnels
            //   pdp_ip/rmnet = cellular
            //   lo / bridge = loopback / NAT64-CLAT translator
            let blockedPrefixes = ["awdl", "llw", "utun", "ipsec", "pdp_ip", "rmnet", "lo", "bridge"]
            if blockedPrefixes.contains(where: { name.hasPrefix($0) }) { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addrPtr, socklen_t(addr.sa_len),
                              &hostname, socklen_t(hostname.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            candidates.append(Candidate(name: name, ip: String(cString: hostname)))
        }

        #if DEBUG
        print("[TVCastDiscovery] interface candidates: \(candidates.map { "\($0.name)=\($0.ip)" }.joined(separator: ", "))")
        #endif

        return candidates.min(by: { rankIPv4($0.ip, name: $0.name) < rankIPv4($1.ip, name: $1.name) })?.ip
    }

    /// Lower is better. Prefers `en0` with an RFC1918 private LAN address,
    /// then any `en*` private address, then any `en*` non-link-local, with
    /// link-locals (169.254.x.x) ranked last because they signal DHCP
    /// hasn't completed.
    nonisolated private static func rankIPv4(_ ip: String, name: String) -> Int {
        let isEn0 = name == "en0"
        let isEnAny = name.hasPrefix("en")
        let isPriv = isPrivateLAN(ip)
        let isLink = ip.hasPrefix("169.254.")

        if isPriv {
            if isEn0 { return 0 }
            if isEnAny { return 1 }
            return 4
        }
        if !isLink {
            if isEn0 { return 2 }
            if isEnAny { return 3 }
            return 5
        }
        // Link-local — only useful as an absolute last resort.
        if isEn0 { return 6 }
        if isEnAny { return 7 }
        return 8
    }

    /// `true` for RFC1918 private-network IPv4 addresses (10/8, 172.16/12,
    /// 192.168/16) — the address ranges actual home/office LANs use.
    nonisolated private static func isPrivateLAN(_ ip: String) -> Bool {
        if ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("10.") { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }

    // MARK: - Mutation (called via TVCastDiscoveryStore)

    fileprivate func mergeFound(_ items: [(id: String, name: String, host: String?, port: UInt16?)], kind: TVDeviceKind) {
        for item in items {
            if let idx = devices.firstIndex(where: { $0.id == item.id }) {
                let existing = devices[idx]
                let newHost = existing.host ?? item.host
                let newPort = existing.port ?? item.port
                // Prefer the more descriptive name if we previously had a
                // placeholder like "Apple TV (192.168.x.x)".
                let newName: String = {
                    if existing.name.contains("(") && !item.name.contains("(") {
                        return item.name
                    }
                    return existing.name
                }()
                devices[idx] = DiscoveredTVDevice(
                    id: existing.id, name: newName, kind: kind,
                    host: newHost, port: newPort
                )
                continue
            }
            devices.append(DiscoveredTVDevice(
                id: item.id, name: item.name, kind: kind,
                host: item.host, port: item.port
            ))
        }
    }

    fileprivate func setLocalIPv4(_ ip: String) { localIPv4 = ip }
    fileprivate func setTotalHosts(_ total: Int) { totalHosts = total }
    fileprivate func incrementScannedHosts() { scannedHosts += 1 }
    fileprivate func recordBonjourEndpoints(_ count: Int) {
        bonjourEndpointsSeen = max(bonjourEndpointsSeen, count)
    }
}

/// Bridge so Network callbacks running on background queues can hand work
/// back to the latest active discovery instance on the main actor.
@MainActor
enum TVCastDiscoveryStore {
    private static weak var current: TVCastDiscovery?

    static func register(_ d: TVCastDiscovery) { current = d }

    static func merge(snapshot: [(id: String, name: String, host: String?, port: UInt16?)], kind: TVDeviceKind) {
        current?.mergeFound(snapshot, kind: kind)
    }

    static func setLocalIPv4(_ ip: String) { current?.setLocalIPv4(ip) }
    static func setTotalHosts(_ total: Int) { current?.setTotalHosts(total) }
    static func incrementScannedHosts() { current?.incrementScannedHosts() }
    static func recordBonjourEndpoints(_ count: Int) { current?.recordBonjourEndpoints(count) }
}
