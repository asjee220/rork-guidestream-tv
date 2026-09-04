//
//  TVSelfName.swift
//  GuideStreamTVTV
//
//  What this Apple TV is called in the house — "Living Room 7", not
//  "Apple TV".
//
//  tvOS 16 redacted `UIDevice.current.name` down to the model name unless
//  the app carries Apple's user-assigned-device-name entitlement, which is
//  request-and-approve. So the TV genuinely cannot say its own name, and
//  Play on TV compared the phone's target against the string "Apple TV"
//  and never matched.
//
//  The Apple TV does publish its name, though: its own AirPlay receiver
//  answers /info on port 7000 with a plist whose `name` is exactly what
//  the user typed in Settings — and it is the same endpoint the phone
//  reads when it builds the device list, so both ends agree by
//  construction. We ask ourselves over loopback, then over our own LAN
//  address if the receiver is not bound to loopback.
//

import Foundation
import Network
import UIKit

@MainActor
final class TVSelfName {
    static let shared = TVSelfName()

    private let storageKey = "gs.tv.selfName"

    /// Best known name for this Apple TV. Falls back to `UIDevice.current.name`
    /// until the AirPlay probe answers, so matching degrades rather than breaks.
    private(set) var name: String

    /// True once the AirPlay probe supplied the name, so callers can tell a
    /// real device name from the "Apple TV" placeholder.
    private(set) var isResolved: Bool

    private var refreshTask: Task<Void, Never>?

    private init() {
        let cached = UserDefaults.standard.string(forKey: storageKey)
        if let cached, !cached.isEmpty {
            name = cached
            isResolved = true
        } else {
            name = UIDevice.current.name
            isResolved = false
        }
    }

    /// Kick off (or re-run) the probe. Cheap, and the name can change when
    /// the user renames the TV in Settings, so this runs on every launch and
    /// on every foreground rather than only when the cache is empty.
    func refresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            defer { self?.refreshTask = nil }
            guard let resolved = await Self.probeAirPlayName() else { return }
            guard let self, resolved != self.name || !self.isResolved else { return }
            self.name = resolved
            self.isResolved = true
            UserDefaults.standard.set(resolved, forKey: self.storageKey)
            #if DEBUG
            print("[TVSelfName] resolved self as '\(resolved)'")
            #endif
        }
    }

    /// Await the probe when the answer is needed now — a play command has
    /// arrived and the cache is still the model name.
    func resolveNow() async {
        guard !isResolved else { return }
        if let resolved = await Self.probeAirPlayName() {
            name = resolved
            isResolved = true
            UserDefaults.standard.set(resolved, forKey: storageKey)
        }
    }

    // MARK: - AirPlay /info probe

    nonisolated private static func probeAirPlayName() async -> String? {
        var hosts = ["127.0.0.1"]
        if let local = localIPv4Address() { hosts.append(local) }
        for host in hosts {
            guard let data = await rawHTTPGetData(host: host, port: 7000, path: "/info", timeout: 2.0),
                  let name = extractAirPlayName(from: data)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else { continue }
            return name
        }
        return nil
    }

    nonisolated private static func extractAirPlayName(from data: Data) -> String? {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            if let n = plist["name"] as? String, !n.isEmpty { return n }
            if let n = plist["deviceName"] as? String, !n.isEmpty { return n }
        }
        if let body = String(data: data, encoding: .utf8),
           let n = plistStringValue(key: "name", in: body) {
            return n
        }
        return nil
    }

    /// `<key>name</key><string>Living Room 7</string>` out of an XML plist.
    nonisolated private static func plistStringValue(key: String, in body: String) -> String? {
        guard let keyRange = body.range(of: "<key>\(key)</key>") else { return nil }
        let rest = body[keyRange.upperBound...]
        guard let open = rest.range(of: "<string>"),
              let close = rest.range(of: "</string>"),
              open.upperBound <= close.lowerBound else { return nil }
        let value = String(rest[open.upperBound..<close.lowerBound])
        return value.isEmpty ? nil : value
    }

    // MARK: - Minimal HTTP over NWConnection

    nonisolated private static func rawHTTPGetData(host: String, port: UInt16, path: String, timeout: TimeInterval) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: nil); return
            }
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)

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

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // The AirPlay UA gets a fuller /info plist back than a
                    // generic one does on some tvOS builds.
                    let req = "GET \(path) HTTP/1.0\r\nHost: \(host)\r\nUser-Agent: AirPlay/540.31\r\nConnection: close\r\nAccept: */*\r\n\r\n"
                    conn.send(content: req.data(using: .utf8), completion: .contentProcessed { _ in })
                    var buffer = Data()
                    func readNext() {
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
                            if let data, !data.isEmpty { buffer.append(data) }
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

    nonisolated private static func findHTTPBodyStart(in data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        var i = 0
        let upper = data.count - 4
        while i <= upper {
            if data[i] == 0x0d, data[i + 1] == 0x0a, data[i + 2] == 0x0d, data[i + 3] == 0x0a {
                return i + 4
            }
            i += 1
        }
        return nil
    }

    /// This device's LAN IPv4, preferring the wired/Wi-Fi interface over the
    /// peer-to-peer and tunnel interfaces that cannot see the house network.
    nonisolated private static func localIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var best: String?
        var bestRank = Int.max
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard let addrPtr = cur.pointee.ifa_addr else { continue }
            let addr = addrPtr.pointee
            guard (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
                  addr.sa_family == UInt8(AF_INET) else { continue }

            let iface = String(cString: cur.pointee.ifa_name)
            let blocked = ["awdl", "llw", "utun", "ipsec", "pdp_ip", "rmnet", "lo", "bridge"]
            if blocked.contains(where: { iface.hasPrefix($0) }) { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addrPtr, socklen_t(addr.sa_len),
                              &hostname, socklen_t(hostname.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: hostname)

            let rank: Int = {
                if ip.hasPrefix("169.254.") { return 3 }
                if iface == "en0" { return 0 }
                if iface.hasPrefix("en") { return 1 }
                return 2
            }()
            if rank < bestRank {
                bestRank = rank
                best = ip
            }
        }
        return best
    }
}
