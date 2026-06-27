//
//  TizenLaunchClient.swift
//  GuideStreamTV
//
//  Controls Samsung Tizen TVs over their v2 WebSocket API.
//  Connects on port 8002 (TLS), accepts the TV's self-signed certificate,
//  handles the pairing token flow, resolves the streaming app id, and
//  launches it via NATIVE_LAUNCH.
//

import Foundation

// MARK: - App ID lookup

/// Maps a streaming platform label to the best-effort Samsung Tizen app ID.
/// These numeric ids are fallbacks only — the installed-app query is the
/// primary, more reliable source.
enum TizenApp {
    static func id(for platform: String) -> String? {
        let key = normalize(platform)

        if key.contains("netflix")              { return "11101200001" }
        if key.contains("youtube")              { return "111299001912" }
        if key.contains("disney")               { return "3201901017640" }
        if key.contains("prime") || key.contains("amazon") { return "3201910019365" }
        if key.contains("hulu")                 { return "3201601007625" }
        if key.contains("hbo") || key.contains("max") { return "3201601007230" }
        if key.contains("apple")                { return "3201807016597" }
        if key.contains("paramount")            { return "3201710015037" }
        if key.contains("peacock")             { return "3201969019359" }
        if key.contains("spotify")              { return "3201606009684" }
        if key.contains("tubi")                 { return "3201504001965" }
        if key.contains("plex")                 { return "3201512006963" }
        return nil
    }

    /// Normalises a platform label the same way RokuChannel.id does.
    static func normalize(_ platform: String) -> String {
        platform
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
    }
}

// MARK: - Launch result

enum TizenLaunchResult: Equatable {
    case ok
    case needsApproval
    case denied
    case unsupported
    case unreachable

    var isSuccess: Bool { self == .ok }
}

// MARK: - Token persistence

enum TizenTokenStore {
    private static let key = "guidestream.tizen.tokens"

    static func token(for deviceId: String) -> String? {
        guard let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String] else {
            return nil
        }
        return dict[deviceId]
    }

    static func save(_ token: String, for deviceId: String) {
        var dict = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        dict[deviceId] = token
        UserDefaults.standard.set(dict, forKey: key)
    }
}

// MARK: - TLS delegate (accepts self-signed cert)

private final class TizenTLSCertDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - Internal models

private struct TizenMessage {
    let event: String?
    let dataToken: String?
    let dataMessage: String?
    let dataApps: [TizenInstalledApp]?
}

private struct TizenInstalledApp {
    let appId: String
    let name: String
    let appType: Int?
}

// MARK: - Actor for session state

private actor TizenSessionState {
    var authResult: TizenLaunchResult?
    var installedApps: [TizenInstalledApp]?
    var token: String?
    var failed = false

    func receive(_ msg: TizenMessage) {
        switch msg.event {
        case "ms.channel.connect":
            if authResult == nil { authResult = .ok }
            if let t = msg.dataToken, !t.isEmpty { token = t }
        case "ms.channel.unauthorized":
            if authResult == nil { authResult = .denied }
        case "ms.error":
            if let em = msg.dataMessage, em.lowercased().contains("unrecognized method value") {
                if authResult == nil { authResult = .unsupported }
            }
        case "ed.installedApp.get":
            if installedApps == nil, let apps = msg.dataApps { installedApps = apps }
        default:
            break
        }
    }

    func setFailed() { failed = true }

    func waitForAuth(timeout: Duration) async -> TizenLaunchResult {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let r = authResult { return r }
            if failed { return .unreachable }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return .needsApproval
    }

    func waitForInstalledApps(timeout: Duration) async -> [TizenInstalledApp]? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let apps = installedApps { return apps }
            if failed { return nil }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }
}

// MARK: - Launch client

enum TizenLaunchClient {

    nonisolated static func launch(
        host: String,
        deviceId: String,
        platform: String
    ) async -> TizenLaunchResult {
        let nameB64 = Data("GuideStream".utf8).base64EncodedString()
        var urlString = "wss://\(host):8002/api/v2/channels/samsung.remote.control?name=\(nameB64)"
        if let existingToken = TizenTokenStore.token(for: deviceId) {
            urlString += "&token=\(existingToken)"
        }

        guard let wsURL = URL(string: urlString) else { return .unreachable }

        let delegate = TizenTLSCertDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.webSocketTask(with: wsURL)
        let state = TizenSessionState()

        // ----- receive loop -----
        let receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let msg = try await task.receive()
                    if let parsed = parseMessage(msg) {
                        await state.receive(parsed)
                    }
                } catch {
                    await state.setFailed()
                    return
                }
            }
        }

        task.resume()

        // Ensure cleanup on every exit path.
        defer {
            receiveTask.cancel()
            task.cancel()
            session.invalidateAndCancel()
        }

        // ----- Phase 1: wait for authorization (12 s) -----
        let authResult = await state.waitForAuth(timeout: .seconds(12))
        guard authResult == .ok else { return authResult }

        // Persist the pairing token so next launch skips the Allow prompt.
        if let token = await state.token {
            TizenTokenStore.save(token, for: deviceId)
        }

        // ----- Phase 2: resolve app id via installed-app query -----
        let query = #"{"method":"ms.channel.emit","params":{"event":"ed.installedApp.get","to":"host"}}"#
        do {
            try await task.send(.string(query))
        } catch {
            return .unreachable
        }

        let apps = await state.waitForInstalledApps(timeout: .seconds(3))
        let platformKey = TizenApp.normalize(platform)
        let canonicalKeys = [
            "netflix", "disney", "paramount", "max", "prime",
            "hulu", "apple", "peacock", "youtube", "spotify", "tubi", "plex"
        ]
        let lookupKey: String = {
            for key in canonicalKeys {
                if platformKey.contains(key) { return key }
            }
            return platformKey
        }()

        let appId: String? = {
            if let apps {
                for app in apps {
                    let normalizedName = TizenApp.normalize(app.name)
                    if normalizedName.contains(lookupKey) {
                        return app.appId
                    }
                }
            }
            // Fall back to static ID mapping.
            return TizenApp.id(for: platform)
        }()

        guard let appId else { return .unsupported }

        // ----- Phase 3: launch the app -----
        let launch = #"{"method":"ms.channel.emit","params":{"event":"ed.apps.launch","to":"host","data":{"action_type":"NATIVE_LAUNCH","appId":"\#(appId)","metaTag":""}}}"#
        do {
            try await task.send(.string(launch))
        } catch {
            return .unreachable
        }

        // Brief wait for the command to be processed.
        try? await Task.sleep(for: .milliseconds(300))
        return .ok
    }

    // MARK: - Private helpers

    nonisolated fileprivate static func parseMessage(_ message: URLSessionWebSocketTask.Message) -> TizenMessage? {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let event = json["event"] as? String
            let dataDict = json["data"] as? [String: Any]

            var apps: [TizenInstalledApp]? = nil
            if let dataArr = dataDict?["data"] as? [[String: Any]] {
                apps = dataArr.compactMap { item in
                    guard let appId = item["appId"] as? String,
                          let name = item["name"] as? String else { return nil }
                    return TizenInstalledApp(
                        appId: appId,
                        name: name,
                        appType: item["app_type"] as? Int
                    )
                }
            }

            return TizenMessage(
                event: event,
                dataToken: dataDict?["token"] as? String,
                dataMessage: dataDict?["message"] as? String,
                dataApps: apps
            )
        case .data:
            return nil
        @unknown default:
            return nil
        }
    }
}
