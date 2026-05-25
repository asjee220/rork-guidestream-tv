//
//  RokuECPClient.swift
//  GuideStreamTV
//
//  Sends launch commands to a Roku device using the External Control Protocol.
//  Docs: https://developer.roku.com/docs/developer-program/dev-tools/external-control-api.md
//

import Foundation

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
    /// Fires an ECP launch request. Returns true if the request was accepted.
    nonisolated static func launch(host: String, port: UInt16, channelId: String, contentId: String? = nil, mediaType: String = "series") async -> Bool {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = "/launch/\(channelId)"
        if let contentId, !contentId.isEmpty {
            components.queryItems = [
                URLQueryItem(name: "contentId", value: contentId),
                URLQueryItem(name: "mediaType", value: mediaType)
            ]
        }
        guard let url = components.url else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 4
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                return (200..<300).contains(http.statusCode)
            }
            return false
        } catch {
            #if DEBUG
            print("[RokuECP] launch failed: \(error)")
            #endif
            return false
        }
    }
}
