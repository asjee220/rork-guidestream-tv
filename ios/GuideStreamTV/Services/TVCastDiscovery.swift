//
//  TVCastDiscovery.swift
//  GuideStreamTV
//
//  Scans the local network for Apple TV (AirPlay) and Roku (ECP) devices using
//  Bonjour via the Network framework.
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
    @ObservationIgnored private var permissionPokeConnection: NWConnection?
    @ObservationIgnored private var permissionPokeListener: NWListener?

    func start() {
        guard !isScanning else { return }
        isScanning = true
        devices = []
        // Forcibly trigger the iOS Local Network permission prompt. NWBrowser
        // alone is not always enough — sending a UDP packet to an mDNS/SSDP
        // multicast address reliably surfaces the system alert, which is also
        // what registers the app in Settings → Privacy → Local Network.
        triggerLocalNetworkPrompt()
        browse(type: "_airplay._tcp", kind: .appleTV)
        browse(type: "_roku-ecp._tcp", kind: .roku)
    }

    func stop() {
        isScanning = false
        for b in browsers { b.cancel() }
        browsers = []
        permissionPokeConnection?.cancel()
        permissionPokeConnection = nil
        try? permissionPokeListener?.cancel()
        permissionPokeListener = nil
    }

    /// Apple's recommended trick for surfacing the Local Network prompt on
    /// demand: advertise a tiny Bonjour service AND fire an outbound UDP
    /// packet to the SSDP multicast group. Either alone is unreliable; the
    /// combination consistently causes iOS to show the alert and register
    /// the app under Settings → Privacy → Local Network.
    private func triggerLocalNetworkPrompt() {
        // 1) Advertise a throwaway Bonjour service so iOS sees us as a
        // legitimate local-network participant.
        if permissionPokeListener == nil {
            let listener = try? NWListener(using: .udp)
            listener?.service = NWListener.Service(name: "GuideStreamTVDiscovery", type: "_guidestreamtv._udp")
            listener?.newConnectionHandler = { c in c.cancel() }
            listener?.start(queue: .main)
            permissionPokeListener = listener
        }

        // 2) Send a single UDP datagram to the SSDP multicast address.
        // This is the action that actually triggers the alert.
        let host = NWEndpoint.Host("239.255.255.250")
        let port = NWEndpoint.Port(rawValue: 1900)!
        let conn = NWConnection(host: host, port: port, using: .udp)
        permissionPokeConnection = conn
        conn.start(queue: .main)
        let probe = Data("M-SEARCH * HTTP/1.1\r\n\r\n".utf8)
        conn.send(content: probe, completion: .contentProcessed { _ in })
    }

    private func browse(type: String, kind: TVDeviceKind) {
        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: params)
        let kindString = kind.rawValue
        browser.browseResultsChangedHandler = { results, _ in
            // Snapshot the Sendable bits we need so we can hop to the main actor.
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

    fileprivate func mergeFound(_ items: [(id: String, name: String, host: String?, port: UInt16?)], kind: TVDeviceKind) {
        for item in items {
            guard !devices.contains(where: { $0.id == item.id }) else { continue }
            devices.append(DiscoveredTVDevice(
                id: item.id,
                name: item.name,
                kind: kind,
                host: item.host,
                port: item.port
            ))
        }
    }
}

/// Lightweight bridge so the @Sendable Bonjour callback can hand work back
/// to the latest active discovery instance without capturing it directly.
@MainActor
enum TVCastDiscoveryStore {
    private static weak var current: TVCastDiscovery?

    static func register(_ d: TVCastDiscovery) { current = d }

    static func merge(snapshot: [(id: String, name: String, host: String?, port: UInt16?)], kind: TVDeviceKind) {
        current?.mergeFound(snapshot, kind: kind)
    }
}
