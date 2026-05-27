//
//  TVCastDiscovery.swift
//  GuideStreamTVTV
//
//  tvOS-compatible stub of the iOS TVCastDiscovery types.
//  On Apple TV there is nothing to discover — the device IS the TV —
//  so the discovery methods are no-ops, but the types must exist so
//  views shared with the iOS target compile cleanly.
//

import Foundation
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
    private(set) var localIPv4: String? = nil
    private(set) var scannedHosts: Int = 0
    private(set) var totalHosts: Int = 0
    private(set) var bonjourEndpointsSeen: Int = 0

    func start() {
        // No-op on tvOS — the device itself is the TV.
    }

    func stop() {
        // No-op on tvOS.
    }

    func probeManualHost(_ rawHost: String) async -> Bool {
        false
    }
}
