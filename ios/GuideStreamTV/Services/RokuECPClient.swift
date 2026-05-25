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

import Foundation
import Network

enum RokuChannel {
    /// Maps a streaming platform label to the Roku channel ID.
    static func id(for platform: String) -> String? {
        let key = platform.lowercased()
        if key.contains("netflix")             { return "12" }
        if key.contains("hbo") || key.contains("max") { return "61322" }
        if key.contains("hulu")                { return "2285" }
        if key.contains("disney")              { return "291097" }
        if key.contains("prime") || key.contains("amazon") { return "13" }
        if key.contains("apple")               { return "551012" }
        if key.contains("paramount")           { return "31440" }
        if key.contains("peacock")             { return "593099" }
        if key.contains("youtube tv")          { return "195316" }
        if key.contains("youtube")             { return "837" }
        if key.contains("showtime")            { return "60308" }
        if key.contains("starz")               { return "151908" }
        if key.contains("crunchyroll")         { return "55307" }
        return nil
    }
}

enum RokuECPClient {

    /// Fires an ECP launch request at the Roku device. Returns `true` if the
    /// device responded with a 2xx status.
    ///
    /// `contentId` is the channel-specific catalog identifier — we pass the
    /// TMDB id as a best-effort hint; most channels will simply ignore an
    /// unrecognised id and open to their home screen, which is the correct
    /// fallback. For channels that DO accept arbitrary identifiers (Jellyfin,
    /// Plex, sideloaded apps) the deep-link will land directly on the title.
    nonisolated static func launch(
        host: String,
        port: UInt16,
        channelId: String,
        contentId: String? = nil,
        mediaType: String = "series"
    ) async -> Bool {
        var path = "/launch/\(channelId)"
        if let contentId, !contentId.isEmpty {
            let cid = contentId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? contentId
            let mt = mediaType.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? mediaType
            // Roku ECP is case-insensitive on parameter names but the public
            // docs use `contentID` / `MediaType`, so we match that exactly.
            path += "?contentID=\(cid)&MediaType=\(mt)"
        }
        return await rawHTTPPost(host: host, port: port, path: path, timeout: 4.0)
    }

    /// Sends `keypress/<key>` to the Roku — useful for resuming playback
    /// or sending Home/Back after a launch. Currently unused but exposed
    /// for future remote-control UI.
    nonisolated static func keypress(host: String, port: UInt16, key: String) async -> Bool {
        await rawHTTPPost(host: host, port: port, path: "/keypress/\(key)", timeout: 2.5)
    }

    // MARK: - Raw HTTP POST (ATS-bypass)

    /// Performs an HTTP/1.0 POST with an empty body via raw NWConnection.
    /// Returns `true` when the receiver writes back any 2xx status line.
    ///
    /// Implementation notes:
    ///   - Roku ECP requires POST (with `-d ''` in curl docs). The `Content-Length: 0`
    ///     header is mandatory; without it Roku waits for body bytes and times out.
    ///   - We use HTTP/1.0 + `Connection: close` so the device terminates the
    ///     stream as soon as it's done writing — we don't need keep-alive.
    nonisolated private static func rawHTTPPost(host: String, port: UInt16, path: String, timeout: TimeInterval) async -> Bool {
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

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(false)
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
                        if error != nil { finish(false); return }
                    })
                    var buffer = Data()
                    func readNext() {
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                            if let data = data, !data.isEmpty { buffer.append(data) }
                            // Once we have any status line, we can decide.
                            if let line = firstResponseLine(in: buffer) {
                                finish(line.contains(" 2"))
                                return
                            }
                            if isComplete || error != nil || buffer.count > 16 * 1024 {
                                finish(false)
                                return
                            }
                            readNext()
                        }
                    }
                    readNext()
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Returns the first line of an HTTP response (the status line, e.g.
    /// `HTTP/1.0 200 OK`) once enough bytes have arrived for a CRLF to appear,
    /// or `nil` if the line isn't complete yet.
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
