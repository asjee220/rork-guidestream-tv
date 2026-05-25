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

    func start() {
        guard !isScanning else { return }
        isScanning = true
        devices = []
        browse(type: "_airplay._tcp", kind: .appleTV)
        browse(type: "_roku-ecp._tcp", kind: .roku)
    }

    func stop() {
        isScanning = false
        for b in browsers { b.cancel() }
        browsers = []
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
