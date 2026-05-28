//
//  TVCastPlaybackState.swift
//  GuideStreamTVTV
//
//  No-op stub for tvOS — CastPlaybackState tracks the active cast session
//  (what's playing, on which TV, on which app). On Apple TV there is no
//  concept of "casting to another device," so this is a compile-time stub.
//

import Foundation

@MainActor
@Observable
final class CastPlaybackState {
    static let shared = CastPlaybackState()

    private(set) var current: ActiveSession?

    private init() {}

    struct ActiveSession: Equatable, Identifiable {
        let id: String
        let title: String
        let platform: String
        let deviceName: String
        let deviceKind: TVDeviceKind
        let host: String?
        let port: UInt16?
        let startedAt: Date

        var canSendKeypress: Bool { false }
    }

    func start(
        title: String,
        platform: String,
        deviceName: String,
        deviceKind: TVDeviceKind,
        host: String?,
        port: UInt16?
    ) {}

    func stop() {}

    func sendHomeToRoku() {}

    func openRokuRemote() {}
}
