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
}

struct DiscoveredTVDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: TVDeviceKind
    let host: String?
    let port: UInt16?

    var subtitle: String {
        switch kind {
        case .appleTV: return "Apple TV"
        case .roku:    return "Roku"
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

        // Active subnet probe — the reliable path for Roku and a great
        // Bonjour fallback for Apple TV.
        startSubnetProbe()
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

        // AirPlay/Apple TV on :7000.
        if let airplayInfo = await Self.rawHTTPGet(host: host, port: 7000, path: "/info", timeout: 3.0),
           Self.looksLikeAirPlay(airplayInfo) {
            let name = Self.plistStringValue(key: "name", in: airplayInfo)
                ?? Self.plistStringValue(key: "deviceName", in: airplayInfo)
                ?? "Apple TV (\(host))"
            mergeFound([(id: "appletv-\(host)", name: name, host: host, port: 7000)], kind: .appleTV)
            return true
        }

        return false
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

        // AirPlay/Apple TV on :7000 — /info endpoint returns a plist.
        if let airplayInfo = await rawHTTPGet(host: host, port: 7000, path: "/info", timeout: 1.0),
           looksLikeAirPlay(airplayInfo) {
            let name = plistStringValue(key: "name", in: airplayInfo)
                ?? plistStringValue(key: "deviceName", in: airplayInfo)
                ?? "Apple TV (\(host))"
            let snapshot: [(id: String, name: String, host: String?, port: UInt16?)] =
                [(id: "appletv-\(host)", name: name, host: host, port: 7000)]
            #if DEBUG
            print("[TVCastDiscovery] found Apple TV \(name) @ \(host)")
            #endif
            await MainActor.run {
                TVCastDiscoveryStore.merge(snapshot: snapshot, kind: .appleTV)
            }
        }
    }

    nonisolated private static func looksLikeAirPlay(_ body: String) -> Bool {
        let lower = body.lowercased()
        return lower.contains("airplay")
            || lower.contains("appletv")
            || lower.contains("apple tv")
            || lower.contains("model")
    }

    /// Performs an HTTP/1.0 GET via raw NWConnection so ATS doesn't block
    /// cleartext requests to LAN IP literals.
    nonisolated private static func rawHTTPGet(host: String, port: UInt16, path: String, timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: nil); return
            }
            let params = NWParameters.tcp
            params.prohibitedInterfaceTypes = [.cellular]
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)

            let lock = NSLock()
            var didResume = false
            let finish: (String?) -> Void = { value in
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
                    let req = "GET \(path) HTTP/1.0\r\nHost: \(host)\r\nUser-Agent: GuideStreamTV/1.0\r\nConnection: close\r\nAccept: */*\r\n\r\n"
                    conn.send(content: req.data(using: .utf8), completion: .contentProcessed { _ in })
                    var buffer = Data()
                    func readNext() {
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
                            if let data = data, !data.isEmpty { buffer.append(data) }
                            if isComplete || error != nil || buffer.count > 64 * 1024 {
                                let raw = String(data: buffer, encoding: .utf8) ?? ""
                                // Strip HTTP headers.
                                if let range = raw.range(of: "\r\n\r\n") {
                                    finish(String(raw[range.upperBound...]))
                                } else {
                                    finish(raw.isEmpty ? nil : raw)
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
