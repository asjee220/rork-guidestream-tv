//
//  TVCastDiscovery.swift
//  GuideStreamTV
//
//  Scans the local network for Apple TV (Bonjour/AirPlay) and Roku devices.
//
//  IMPORTANT: SSDP multicast on iOS requires the Apple-gated
//  `com.apple.developer.networking.multicast` entitlement and silently fails
//  without it. We instead actively probe every host on the local /24 subnet.
//  Roku exposes ECP on port 8060 and AirPlay listens on 7000.
//
//  We use raw `NWConnection` TCP sockets (NOT `URLSession`) because App
//  Transport Security blocks cleartext HTTP to IP literals — every URLSession
//  request to 192.168.x.x silently fails. NWConnection isn't governed by ATS,
//  so we can connect to the LAN device, write an HTTP/1.0 request by hand,
//  and read the response. No entitlements required.
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

    @ObservationIgnored private var browsers: [NWBrowser] = []
    @ObservationIgnored private var permissionPokeListener: NWListener?
    @ObservationIgnored private var subnetScanTask: Task<Void, Never>?

    func start() {
        guard !isScanning else { return }
        isScanning = true
        devices = []
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
            Task { @MainActor in
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
            let parts = localIP.split(separator: ".")
            guard parts.count == 4 else { return }
            let prefix = "\(parts[0]).\(parts[1]).\(parts[2])."
            #if DEBUG
            print("[TVCastDiscovery] probing subnet \(prefix)0/24")
            #endif

            // Probe in batches to avoid socket exhaustion.
            let allHosts = (1...254).map { "\(prefix)\($0)" }
            let batchSize = 32
            var index = 0
            while index < allHosts.count {
                if Task.isCancelled { return }
                let end = min(index + batchSize, allHosts.count)
                await withTaskGroup(of: Void.self) { group in
                    for host in allHosts[index..<end] {
                        group.addTask { await Self.probe(host: host) }
                    }
                }
                index = end
            }
        }
    }

    private static func probe(host: String) async {
        // Roku ECP on :8060 — XML device-info; cheap and reliable.
        if let rokuInfo = await rawHTTPGet(host: host, port: 8060, path: "/query/device-info", timeout: 1.5),
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
        if let airplayInfo = await rawHTTPGet(host: host, port: 7000, path: "/info", timeout: 1.5),
           airplayInfo.lowercased().contains("airplay") || airplayInfo.lowercased().contains("appletv") || airplayInfo.lowercased().contains("apple tv") {
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

    /// Performs an HTTP/1.0 GET via raw NWConnection so ATS doesn't block
    /// cleartext requests to LAN IP literals.
    private static func rawHTTPGet(host: String, port: UInt16, path: String, timeout: TimeInterval) async -> String? {
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

    private static func extractTag(_ tag: String, from xml: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let s = xml.range(of: open),
              let e = xml.range(of: close, range: s.upperBound..<xml.endIndex) else { return nil }
        return String(xml[s.upperBound..<e.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plistStringValue(key: String, in plist: String) -> String? {
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
    nonisolated private static func localIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let addr = cur.pointee.ifa_addr.pointee
            // Up + running + not loopback, IPv4.
            if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
               addr.sa_family == UInt8(AF_INET) {
                let name = String(cString: cur.pointee.ifa_name)
                // en0 = Wi-Fi on iPhone; en1/en2 sometimes.
                if name.hasPrefix("en") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(cur.pointee.ifa_addr, socklen_t(cur.pointee.ifa_addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                        break
                    }
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return address
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
}
