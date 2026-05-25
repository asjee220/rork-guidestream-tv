//
//  TVCastDiscovery.swift
//  GuideStreamTV
//
//  Scans the local network for Apple TV (AirPlay via Bonjour/mDNS) and Roku
//  (SSDP/UPnP on UDP 1900) devices. Roku does NOT advertise via Bonjour, so
//  it requires a real SSDP M-SEARCH exchange — that's the part most apps get
//  wrong.
//

import Foundation
import Network
import Observation

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
    @ObservationIgnored private var ssdpConnection: NWConnection?
    @ObservationIgnored private var permissionPokeListener: NWListener?

    func start() {
        guard !isScanning else { return }
        isScanning = true
        devices = []
        // Advertise a throwaway Bonjour service so iOS registers us as a
        // local-network participant (also helps surface the permission prompt).
        startPermissionPokeListener()
        // Apple TV: real Bonjour browse.
        browseBonjour(type: "_airplay._tcp", kind: .appleTV)
        // Roku: SSDP M-SEARCH over UDP multicast. Roku does NOT use Bonjour.
        startSSDPDiscovery()
    }

    func stop() {
        isScanning = false
        for b in browsers { b.cancel() }
        browsers = []
        ssdpConnection?.cancel()
        ssdpConnection = nil
        permissionPokeListener?.cancel()
        permissionPokeListener = nil
    }

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
        TVCastDiscoveryStore.register(self)
    }

    // MARK: - SSDP (Roku)

    private func startSSDPDiscovery() {
        let host = NWEndpoint.Host("239.255.255.250")
        guard let port = NWEndpoint.Port(rawValue: 1900) else { return }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let conn = NWConnection(host: host, port: port, using: params)
        ssdpConnection = conn

        conn.stateUpdateHandler = { [weak self] state in
            #if DEBUG
            print("[TVCastDiscovery] SSDP state: \(state)")
            #endif
            if case .ready = state {
                Task { @MainActor in
                    guard let self else { return }
                    self.sendSSDPSearch(conn)
                    self.receiveSSDP(conn)
                }
            }
        }
        conn.start(queue: .main)

        // Re-send the M-SEARCH a couple of times — UDP can drop and Roku's
        // MX random delay means a single probe sometimes misses devices.
        Task { @MainActor [weak self] in
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, let c = self.ssdpConnection, c.state == .ready else { return }
                self.sendSSDPSearch(c)
            }
        }
    }

    private func sendSSDPSearch(_ conn: NWConnection) {
        let msearch =
            "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: 239.255.255.250:1900\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "ST: roku:ecp\r\n" +
            "MX: 3\r\n" +
            "\r\n"
        conn.send(content: Data(msearch.utf8), completion: .contentProcessed { _ in })
    }

    private func receiveSSDP(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            Task { @MainActor in
                guard let self else { return }
                if let text { self.handleSSDPResponse(text) }
                if conn.state != .cancelled {
                    self.receiveSSDP(conn)
                }
            }
        }
    }

    private func handleSSDPResponse(_ text: String) {
        // We only care about Roku responses. They include a LOCATION header
        // pointing at the ECP endpoint, e.g. "http://192.168.1.50:8060/".
        let lowered = text.lowercased()
        guard lowered.contains("roku") || lowered.contains("ecp") else { return }

        var location: String?
        var usn: String?
        for rawLine in text.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
            let line = String(rawLine)
            if let range = line.range(of: "LOCATION:", options: .caseInsensitive) {
                location = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if let range = line.range(of: "USN:", options: .caseInsensitive) {
                usn = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }

        guard let loc = location, let url = URL(string: loc),
              let host = url.host else { return }
        let port = UInt16(url.port ?? 8060)
        let id = "roku-\(usn ?? "\(host):\(port)")"
        let name = "Roku (\(host))"

        let snapshot: [(id: String, name: String, host: String?, port: UInt16?)] =
            [(id: id, name: name, host: host, port: port)]
        Task { @MainActor in
            TVCastDiscoveryStore.merge(snapshot: snapshot, kind: .roku)
            // Fetch the friendly name asynchronously from the device-info endpoint.
            await TVCastDiscoveryStore.refineRokuName(deviceId: id, host: host, port: port)
        }
    }

    fileprivate func mergeFound(_ items: [(id: String, name: String, host: String?, port: UInt16?)], kind: TVDeviceKind) {
        for item in items {
            if let idx = devices.firstIndex(where: { $0.id == item.id }) {
                // Update host/port if we just learned them.
                if devices[idx].host == nil, item.host != nil {
                    devices[idx] = DiscoveredTVDevice(
                        id: item.id, name: devices[idx].name,
                        kind: kind, host: item.host, port: item.port
                    )
                }
                continue
            }
            devices.append(DiscoveredTVDevice(
                id: item.id,
                name: item.name,
                kind: kind,
                host: item.host,
                port: item.port
            ))
        }
    }

    fileprivate func renameDevice(id: String, to newName: String) {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return }
        let d = devices[idx]
        devices[idx] = DiscoveredTVDevice(id: d.id, name: newName, kind: d.kind, host: d.host, port: d.port)
    }
}

/// Lightweight bridge so @Sendable Network callbacks can hand work back
/// to the latest active discovery instance.
@MainActor
enum TVCastDiscoveryStore {
    private static weak var current: TVCastDiscovery?

    static func register(_ d: TVCastDiscovery) { current = d }

    static func merge(snapshot: [(id: String, name: String, host: String?, port: UInt16?)], kind: TVDeviceKind) {
        current?.mergeFound(snapshot, kind: kind)
    }

    /// Hits the Roku ECP `/query/device-info` endpoint to get the friendly
    /// user-given name (e.g. "Living Room Roku") and updates the row.
    static func refineRokuName(deviceId: String, host: String, port: UInt16) async {
        guard let url = URL(string: "http://\(host):\(port)/query/device-info") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let xml = String(data: data, encoding: .utf8) else { return }
            let name = extractTag("user-device-name", from: xml)
                ?? extractTag("friendly-device-name", from: xml)
                ?? extractTag("model-name", from: xml)
            if let name, !name.isEmpty {
                current?.renameDevice(id: deviceId, to: name)
            }
        } catch {
            // Silent — we'll just keep the IP-based fallback name.
        }
    }

    private static func extractTag(_ tag: String, from xml: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let s = xml.range(of: open), let e = xml.range(of: close, range: s.upperBound..<xml.endIndex) else { return nil }
        return String(xml[s.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
