//
//  RokuECPClient.swift
//  GuideStreamTV
//
//  Sends launch commands to a Roku device using the External Control Protocol.
//  Docs: https://developer.roku.com/docs/developer-program/dev-tools/external-control-api.md
//
//  IMPORTANT: ECP is plain HTTP on port 8060. iOS App Transport Security blocks
//  cleartext requests to LAN IP literals (192.168.x.x) through URLSession by
//  default — those requests die before they leave the device with no useful
//  error. We bypass ATS by writing the HTTP/1.0 POST by hand over a raw
//  NWConnection TCP socket. NWConnection isn't governed by ATS, so cleartext
//  LAN traffic goes through cleanly.
//
//  Roku OS 14.1+ note: As of December 2024, the "Network access" sub-setting
//  under Settings → System → Advanced → Control by mobile apps defaults to
//  "Limited mode", which causes the Roku to reject `launch` and `keypress`
//  requests with HTTP 403 from devices it hasn't paired with via the Roku
//  app. This is by far the most common reason cast-to-Roku fails today, so
//  the launch result type explicitly distinguishes that case so the UI can
//  guide users to flip the setting to "Permissive" or "Enabled".
//

import Foundation
import Network

enum RokuChannel {
    /// Maps a streaming platform label to the Roku channel ID.
    /// Normalises dashes, underscores, and parentheses before matching
    /// so strings like "netflix-4k", "Amazon Prime Video", or "prime_video"
    /// all resolve correctly.
    static func id(for platform: String) -> String? {
        let key = platform
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()

        if key.contains("netflix")              { return "12" }
        if key.contains("hbo") || key.contains(" max") || key.hasSuffix("max") { return "61322" }
        if key.contains("hulu")                { return "2285" }
        if key.contains("disney")              { return "291097" }
        if key.contains("prime") || key.contains("amazon") { return "13" }
        if key.contains("apple tv") || key.contains("appletv") || key.contains("apple ") { return "551012" }
        if key.contains("paramount")           { return "31440" }
        if key.contains("peacock")             { return "593099" }
        if key.contains("youtube tv") || key.contains("youtubetv") { return "195316" }
        if key.contains("youtube")             { return "837" }
        if key.contains("showtime")            { return "60308" }
        if key.contains("starz")               { return "151908" }
        if key.contains("crunchyroll")         { return "55307" }
        if key.contains("tubi")                { return "41468" }
        if key.contains("pluto")               { return "74519" }
        if key.contains("plex")                { return "13535" }
        return nil
    }
}

/// Outcome of a Roku ECP launch attempt. Lets the UI tell the user *why*
/// a launch failed instead of just "couldn't reach device".
enum RokuLaunchResult: Equatable {
    /// The channel opened (Roku replied 2xx).
    case ok
    /// Roku replied 401/403 — almost always means the user has
    /// "Network access" set to Limited mode under
    /// Settings → System → Advanced system settings → Control by mobile apps.
    /// The fix is to switch it to "Permissive" or "Enabled".
    case limitedMode
    /// Roku is reachable but rejected the launch (404 unknown channel id,
    /// 500, etc.). The associated value is the HTTP status when available.
    case rejected(Int)
    /// The HTTP request never completed — wrong host, device offline,
    /// AP isolation, VPN blocking LAN traffic, etc.
    case unreachable

    var isSuccess: Bool { self == .ok }
}

/// Lower-level result for a single raw HTTP request — exposes the HTTP
/// status code so `launch` can classify the failure.
private enum RokuHTTPOutcome {
    case status(Int)
    case timeout
    case socketFailure
}

enum RokuECPClient {

    // MARK: - ECP status check (pre-launch)

    /// Outcome of probing `/query/device-info` before attempting a launch.
    /// Lets the UI route to the limited-mode help screen *before* we burn
    /// the Home-keypress + 1.5s sleep on a device that will always 403.
    enum ECPStatus { case enabled, limited, unreachable }

    /// Checks whether ECP is enabled on the Roku device by probing
    /// /query/device-info via raw HTTP GET.
    ///
    /// - `.enabled`  — ECP is working, proceed with launch.
    /// - `.limited`  — Device is in limited mode (403 response). User must
    ///   enable "Control by mobile apps" in Roku settings.
    /// - `.unreachable` — No response within timeout (wrong IP, device off,
    ///   firewall, or different network).
    nonisolated static func checkECPEnabled(host: String, port: UInt16) async -> ECPStatus {
        await withCheckedContinuation { (continuation: CheckedContinuation<ECPStatus, Never>) in
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: .unreachable); return
            }
            let params = NWParameters.tcp
            params.prohibitedInterfaceTypes = [.cellular]
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)

            let lock = NSLock()
            var didResume = false
            let finish: (ECPStatus) -> Void = { value in
                lock.lock()
                let already = didResume
                didResume = true
                lock.unlock()
                if already { return }
                conn.cancel()
                continuation.resume(returning: value)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                finish(.unreachable)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let req = "GET /query/device-info HTTP/1.0\r\n"
                        + "Host: \(host)\r\n"
                        + "Connection: close\r\n\r\n"
                    conn.send(content: req.data(using: .utf8), completion: .contentProcessed { _ in })
                    var buffer = Data()
                    func readNext() {
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                            if let data = data { buffer.append(data) }
                            if let line = firstResponseLine(in: buffer) {
                                if line.contains(" 403") {
                                    finish(.limited)
                                } else if line.contains(" 2") {
                                    finish(.enabled)
                                } else {
                                    finish(.unreachable)
                                }
                                return
                            }
                            if isComplete || error != nil { finish(.unreachable); return }
                            readNext()
                        }
                    }
                    readNext()
                case .failed, .cancelled:
                    finish(.unreachable)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Fires an ECP launch request at the Roku device.
    ///
    /// `contentId` is the channel-specific catalog identifier — we pass the
    /// TMDB id as a best-effort hint; most first-party channels (Netflix,
    /// Hulu, Max, etc.) use their own internal IDs and will ignore an
    /// unrecognised value, simply opening to their landing screen. For
    /// channels that DO accept arbitrary identifiers (Jellyfin, Plex,
    /// sideloaded apps) the deeplink lands directly on the title.
    ///
    /// Attempt order:
    ///   1. `/launch/<id>?contentId=<id>&mediaType=<type>` — modern lowercase
    ///      params per Roku's current developer docs.
    ///   2. `/launch/<id>?contentID=<id>&MediaType=<type>` — legacy capitalised
    ///      params; some older channels expected this exact case.
    ///   3. `/launch/<id>` — bare launch, opens the channel home. This is the
    ///      "did we reach the box at all?" probe.
    ///
    /// Sends `/keypress/Home` first so the channel always launches from a
    /// known state, then waits for the Home transition to finish before
    /// sending the launch command. On TCL Roku TVs the launch is silently
    /// dropped if it arrives mid-animation. On Roku OS 14.1+ in Limited mode
    /// the Home keypress returns 403, but that's harmless — the launch still
    /// proceeds and either succeeds (channel opens over whatever was on
    /// screen) or returns `.limitedMode`.
    /// Launches a Roku channel using a Watchmode `roku_url` path — a relative
    /// ECP launch string of the form `launch/{channelId}?contentID={contentId}`.
    /// Watchmode resolves these per-source on its paid plan; on the free plan
    /// the field is `nil` and callers should fall back to `launch(host:port:channelId:contentId:mediaType:)`.
    ///
    /// Normalisation handles both bare relative paths and full URLs that happen
    /// to contain a `launch/` segment (e.g. `https://therokuchannel.roku.com/...launch/2285?...`).
    /// If the input can't be reduced to a usable ECP path, the method returns
    /// `.unreachable` without making any request so the caller can fall back.
    nonisolated static func launch(
        host: String,
        port: UInt16,
        rokuURLPath rawPath: String
    ) async -> RokuLaunchResult {
        // Normalise the input — strip schemes, keep only the ECP path portion.
        var normalized = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.contains("://"),
           let launchRange = normalized.range(of: "launch/") {
            normalized = String(normalized[launchRange.lowerBound...])
        }
        if normalized.hasPrefix("/") {
            normalized = String(normalized.dropFirst())
        }
        guard normalized.contains("launch/") else {
            return .unreachable
        }

        // Send Home first so the channel always launches from a known state.
        _ = await rawHTTPPost(host: host, port: port, path: "/keypress/Home", timeout: 2.0)
        try? await Task.sleep(for: .milliseconds(1200))

        let outcome = await rawHTTPPost(host: host, port: port, path: "/" + normalized, timeout: 4.0)
        switch outcome {
        case .status(let code):
            if (200..<300).contains(code) {
                return .ok
            }
            if code == 401 || code == 403 {
                return .limitedMode
            }
            // Bare-launch fallback: parse the channel ID between "launch/" and
            // the first "?" (or end of string) and open the channel home.
            let channelPart = normalized
                .replacingOccurrences(of: "launch/", with: "")
            let channelId = channelPart.components(separatedBy: "?").first ?? channelPart
            let fallbackOutcome = await rawHTTPPost(
                host: host, port: port,
                path: "/launch/\(channelId)", timeout: 4.0
            )
            if case .status(let fbCode) = fallbackOutcome, (200..<300).contains(fbCode) {
                return .ok
            }
            if case .status(let fbCode) = fallbackOutcome {
                return .rejected(fbCode)
            }
            return .rejected(code)
        case .timeout, .socketFailure:
            return .unreachable
        }
    }

    nonisolated static func launch(
        host: String,
        port: UInt16,
        channelId: String,
        contentId: String? = nil,
        mediaType: String = "series"
    ) async -> RokuLaunchResult {
        // Send Home first so we always launch from a known state.
        // TCL Roku TVs silently drop the launch if it arrives while
        // the Home transition is still animating. That animation takes
        // 1.2–1.8s, so we wait 1500ms as the safe minimum — at 900ms the
        // launch could still land mid-transition and the contentId gets
        // dropped, opening the channel home screen instead of the title.
        _ = await rawHTTPPost(host: host, port: port, path: "/keypress/Home", timeout: 2.0)
        try? await Task.sleep(for: .milliseconds(1500))

        // Build the candidate paths in priority order.
        var paths: [String] = []
        if let contentId, !contentId.isEmpty {
            let cid = contentId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? contentId
            let mt = mediaType.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? mediaType
            paths.append("/launch/\(channelId)?contentId=\(cid)&mediaType=\(mt)")
            paths.append("/launch/\(channelId)?contentID=\(cid)&MediaType=\(mt)")
        }
        paths.append("/launch/\(channelId)")

        var sawForbidden = false
        var lastNonOkStatus: Int? = nil

        for path in paths {
            let outcome = await rawHTTPPost(host: host, port: port, path: path, timeout: 4.0)
            switch outcome {
            case .status(let code):
                if (200..<300).contains(code) {
                    return .ok
                }
                if code == 401 || code == 403 {
                    sawForbidden = true
                } else {
                    lastNonOkStatus = code
                }
            case .timeout, .socketFailure:
                // Network-level failure — try the next variant, but if every
                // attempt is a socket failure we'll fall through to .unreachable.
                continue
            }
        }

        if sawForbidden { return .limitedMode }
        if let lastNonOkStatus { return .rejected(lastNonOkStatus) }
        return .unreachable
    }

    /// Sends `keypress/<key>` to the Roku — useful for sending Home/Back
    /// after a launch (e.g. dismissing the active session via the home
    /// banner). Best-effort; returns `false` for any non-2xx response or
    /// network failure. Public so `CastPlaybackState` can reuse it.
    ///
    /// NOTE: On Roku OS 14.1+, this returns 403 unless the user has set
    /// "Network access" to "Permissive" or "Enabled". Callers should treat
    /// failure here as advisory, not fatal.
    nonisolated static func keypress(host: String, port: UInt16, key: String) async -> Bool {
        let outcome = await rawHTTPPost(host: host, port: port, path: "/keypress/\(key)", timeout: 2.5)
        if case .status(let code) = outcome, (200..<300).contains(code) {
            return true
        }
        return false
    }

    /// Cheap reachability probe — sends `GET /query/device-info` (always
    /// allowed by Roku, even in Limited mode) and returns true if the device
    /// replies with anything. Used to differentiate "device offline / wrong
    /// IP" from "device online but rejecting commands".
    nonisolated static func isReachable(host: String, port: UInt16) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: false); return
            }
            let params = NWParameters.tcp
            params.prohibitedInterfaceTypes = [.cellular]
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)

            let lock = NSLock()
            var didResume = false
            let finish: (Bool) -> Void = { value in
                lock.lock()
                let already = didResume
                didResume = true
                lock.unlock()
                if already { return }
                conn.cancel()
                continuation.resume(returning: value)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { finish(false) }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let req = "GET /query/device-info HTTP/1.0\r\nHost: \(host)\r\nConnection: close\r\n\r\n"
                    conn.send(content: req.data(using: .utf8), completion: .contentProcessed { _ in })
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 256) { data, _, _, _ in
                        finish(!(data?.isEmpty ?? true))
                    }
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Extracts the platform-native content ID from a Watchmode web_url.
    /// This is the ID Roku ECP needs for deep linking into a specific title.
    ///
    /// Examples:
    /// https://www.netflix.com/title/80057281 → "80057281"
    /// https://www.amazon.com/dp/B01N4AH0XV → "B01N4AH0XV"
    /// https://www.hulu.com/series/ancient-aliens-xx → "ancient-aliens-xx"
    /// https://www.disneyplus.com/series/foo/barId → "barId"
    /// https://www.max.com/shows/foo/uuid-here → "uuid-here"
    nonisolated static func extractContentId(fromWebURL urlString: String, platform: String) -> String? {
        guard let comps = URLComponents(string: urlString),
              let host = comps.host else { return nil }
        let path = comps.path
        let hostLower = host.lowercased()
        let key = platform.lowercased()

        // Netflix: /title/{id}
        if hostLower.contains("netflix") || key.contains("netflix") {
            let parts = path.split(separator: "/").map(String.init)
            if let idx = parts.firstIndex(of: "title"), idx + 1 < parts.count {
                return parts[idx + 1]
            }
            return parts.last
        }

        // Amazon Prime Video: /dp/{ASIN} or /gp/video/detail/{ASIN}
        if hostLower.contains("amazon") || key.contains("prime") || key.contains("amazon") {
            let parts = path.split(separator: "/").map(String.init)
            if let idx = parts.firstIndex(of: "dp"), idx + 1 < parts.count {
                return parts[idx + 1]
            }
            if let idx = parts.firstIndex(of: "detail"), idx + 1 < parts.count {
                return parts[idx + 1]
            }
            return parts.last
        }

        // Hulu: /series/{slug} or /movie/{slug} or /watch/{id}
        if hostLower.contains("hulu") || key.contains("hulu") {
            let parts = path.split(separator: "/").map(String.init)
            if let idx = parts.firstIndex(where: { $0 == "series" || $0 == "movie" || $0 == "watch" }),
               idx + 1 < parts.count {
                return parts[idx + 1]
            }
            return parts.last
        }

        // Disney+: last non-empty path component is the content ID
        if hostLower.contains("disneyplus") || key.contains("disney") {
            return path.split(separator: "/").last.map(String.init)
        }

        // Max (HBO Max): last path component is UUID
        if hostLower.contains("max.com") || key.contains("hbo") || key.contains(" max") {
            return path.split(separator: "/").last.map(String.init)
        }

        // Paramount+: /shows/{slug} or /movies/{slug}
        if hostLower.contains("paramount") || key.contains("paramount") {
            let parts = path.split(separator: "/").map(String.init)
            if let idx = parts.firstIndex(where: { $0 == "shows" || $0 == "movies" }),
               idx + 1 < parts.count {
                return parts[idx + 1]
            }
            return parts.last
        }

        // Peacock, Apple TV+, and others: last path component
        return path.split(separator: "/").last.map(String.init)
    }

    // MARK: - Raw HTTP POST (ATS-bypass)

    /// Performs an HTTP/1.0 POST with an empty body via raw NWConnection.
    /// Returns the parsed HTTP status code, or a non-status outcome when the
    /// connection itself failed (timeout, refused, etc.).
    ///
    /// Implementation notes:
    ///   - Roku ECP requires POST (with `-d ''` in curl docs). The `Content-Length: 0`
    ///     header is mandatory; without it Roku waits for body bytes and times out.
    ///   - We use HTTP/1.0 + `Connection: close` so the device terminates the
    ///     stream as soon as it's done writing — we don't need keep-alive.
    nonisolated private static func rawHTTPPost(host: String, port: UInt16, path: String, timeout: TimeInterval) async -> RokuHTTPOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<RokuHTTPOutcome, Never>) in
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: .socketFailure); return
            }
            let params = NWParameters.tcp
            params.prohibitedInterfaceTypes = [.cellular]
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)

            let lock = NSLock()
            var didResume = false
            let finish: (RokuHTTPOutcome) -> Void = { value in
                lock.lock()
                let already = didResume
                didResume = true
                lock.unlock()
                if already { return }
                conn.cancel()
                continuation.resume(returning: value)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(.timeout)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let req = "POST \(path) HTTP/1.0\r\n"
                        + "Host: \(host)\r\n"
                        + "User-Agent: GuideStreamTV-ECP/1.0\r\n"
                        + "Content-Length: 0\r\n"
                        + "Connection: close\r\n\r\n"
                    conn.send(content: req.data(using: .utf8), completion: .contentProcessed { error in
                        if error != nil { finish(.socketFailure); return }
                    })
                    var buffer = Data()
                    func readNext() {
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                            if let data = data, !data.isEmpty { buffer.append(data) }
                            // Once we have any status line, we can decide.
                            if let code = parseStatusCode(in: buffer) {
                                finish(.status(code))
                                return
                            }
                            if isComplete || error != nil || buffer.count > 16 * 1024 {
                                finish(.socketFailure)
                                return
                            }
                            readNext()
                        }
                    }
                    readNext()
                case .failed, .cancelled:
                    finish(.socketFailure)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Parses the HTTP status code from a buffer that may contain a partial
    /// or complete response. Returns nil if the status line hasn't fully
    /// arrived yet (no CRLF terminator). Expects an HTTP/1.x response line
    /// like `HTTP/1.0 200 OK` or `HTTP/1.1 403 Forbidden`.
    nonisolated private static func parseStatusCode(in data: Data) -> Int? {
        guard let line = firstResponseLine(in: data) else { return nil }
        // Format: HTTP/<ver> <code> <reason>
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, let code = Int(parts[1]) else { return nil }
        return code
    }

    /// Returns the first line of an HTTP response once enough bytes have
    /// arrived for a CRLF to appear, or `nil` if the line isn't complete yet.
    nonisolated private static func firstResponseLine(in data: Data) -> String? {
        let crlf: [UInt8] = [0x0d, 0x0a]
        guard data.count >= 2 else { return nil }
        var i = 0
        let upper = data.count - 2
        while i <= upper {
            if data[i] == crlf[0] && data[i + 1] == crlf[1] {
                return String(data: data.subdata(in: 0..<i), encoding: .utf8)
            }
            i += 1
        }
        return nil
    }
}
