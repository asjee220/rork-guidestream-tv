//
//  SupportRequestService.swift
//  GuideStreamTV
//
//  GUI-87 — in-app support requests instead of a mailto: hand-off.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Posts a support request to the `support_request` edge function — the same
/// function that already backs the website form.
///
/// The row lands in `support_requests` with `channel = "app"` and the app
/// version, build, device model, OS version and device id attached, so the
/// existing support triage picks it up unchanged. Row-level security denies
/// every client insert on that table (the function writes with the service
/// role), so this is the only path an app has.
///
/// Deployed with `verify_jwt = false`, so the anon key is sufficient and
/// guests can write in too.
enum SupportRequestService {

    /// The topic vocabulary the website support form already uses.
    static let topics = [
        "Something is broken",
        "I have a question",
        "Feature request",
        "Account or billing"
    ]

    /// Submits a request. Returns true only on a 2xx; every failure returns
    /// false so the form can keep the customer's text on screen for a retry.
    static func submit(
        name: String,
        email: String,
        topic: String,
        message: String
    ) async -> Bool {
        let base = SupabaseConfig.url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(base)/functions/v1/support_request") else { return false }

        var payload: [String: Any] = [
            "name": name,
            "email": email,
            "topic": topic,
            "message": message,
            "channel": "app",
            "subject": "GuideStream TV — \(topic)",
            "app_version": appVersion,
            "build": buildNumber,
            "device_model": deviceModel,
            "os_version": osVersion
        ]
        payload["device_id"] = DeviceIdentity.shared.deviceId

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// The marketing model identifier ("iPhone15,3") rather than UIDevice's
    /// generic "iPhone", so support can tell a 13 mini from a 15 Pro Max.
    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) ?? "" }
        }
        return identifier.isEmpty ? "Apple device" : identifier
    }

    static var osVersion: String {
        #if os(tvOS)
        return "tvOS \(UIDevice.current.systemVersion)"
        #elseif canImport(UIKit)
        return "iOS \(UIDevice.current.systemVersion)"
        #else
        return "Apple"
        #endif
    }
}
