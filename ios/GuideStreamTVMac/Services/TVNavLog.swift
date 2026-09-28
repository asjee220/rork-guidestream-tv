//
//  TVNavLog.swift
//  GuideStreamTVTV
//
//  Temporary instrumentation for GUI-92. Every remote input that reaches a
//  navigation handler prints one line tagged [GSNAV], so the Xcode console
//  can be filtered to it while testing on a real Apple TV — the only place
//  touch-surface swipes can be produced at all.
//
//  Remove once swipe navigation is confirmed.
//

import Foundation

enum TVNavLog {
    static func log(_ message: String) {
        print("[GSNAV] \(message)")
    }
}
