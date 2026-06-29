//
//  TVTrailerResolver.swift
//  GuideStreamTVTV
//
//  Resolves a YouTube trailer key into a stream URL that AVPlayer can play
//  natively on tvOS.
//
//  Why this exists: tvOS has no WKWebView, so the phone app's YouTube IFrame
//  embed can't be reused. Instead we ask YouTube's InnerTube `player` endpoint
//  using the IOS client context, which returns an `hlsManifestUrl` (and/or
//  progressive `formats`) with un-ciphered URLs that AVPlayer plays directly —
//  the same trick AirPlay/HLS YouTube shortcuts use. Resolved URLs are
//  IP/region-bound and expire after a few hours, so we cache per session and
//  re-resolve on demand.
//

import Foundation

nonisolated struct TVTrailerResolver {
    static let shared = TVTrailerResolver()

    // Standard InnerTube key + IOS client identifiers. The IOS client is the
    // one that returns playable HLS manifests without signature ciphering.
    private let innerTubeKey = "AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc"
    private let clientVersion = "20.03.02"
    private let clientNameHeader = "5"
    private let endpoint = "https://www.youtube.com/youtubei/v1/player"

    /// Returns the best AVPlayer-compatible stream URL for a YouTube video id,
    /// preferring the HLS manifest (adaptive, tvOS-friendly) and falling back
    /// to a muxed progressive format. Returns nil if nothing is playable.
    func streamURL(for videoKey: String) async -> URL? {
        guard !videoKey.isEmpty,
              var comps = URLComponents(string: endpoint) else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "key", value: innerTubeKey),
            URLQueryItem(name: "prettyPrint", value: "false")
        ]
        guard let url = comps.url else { return nil }

        let body: [String: Any] = [
            "videoId": videoKey,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "context": [
                "client": [
                    "clientName": "IOS",
                    "clientVersion": clientVersion,
                    "deviceModel": "iPhone16,2",
                    "hl": "en",
                    "gl": "US"
                ]
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientNameHeader, forHTTPHeaderField: "X-YouTube-Client-Name")
        req.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        req.setValue(
            "com.google.ios.youtube/\(clientVersion) (iPhone16,2; U; CPU iOS 18_2 like Mac OS X)",
            forHTTPHeaderField: "User-Agent"
        )
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(TVPlayerResponse.self, from: data)
            guard let streaming = decoded.streamingData else { return nil }

            if let hls = streaming.hlsManifestUrl, let u = URL(string: hls) {
                return u
            }
            // Progressive muxed fallback (audio+video in one file).
            if let muxed = streaming.formats?.first(where: { $0.url != nil })?.url,
               let u = URL(string: muxed) {
                return u
            }
            if let adaptive = streaming.adaptiveFormats?.first(where: { $0.url != nil })?.url,
               let u = URL(string: adaptive) {
                return u
            }
            return nil
        } catch {
            return nil
        }
    }
}

// MARK: - InnerTube decoding

private nonisolated struct TVPlayerResponse: Decodable, Sendable {
    let streamingData: TVStreamingData?
}

private nonisolated struct TVStreamingData: Decodable, Sendable {
    let hlsManifestUrl: String?
    let formats: [TVStreamFormat]?
    let adaptiveFormats: [TVStreamFormat]?
}

private nonisolated struct TVStreamFormat: Decodable, Sendable {
    let url: String?
}
