//
//  TVSupportRequestService.swift
//  GuideStreamTVTV
//
//  GUI-87 — in-app support requests on tvOS.
//

import Foundation
import UIKit

/// tvOS counterpart to the iOS `SupportRequestService`.
///
/// tvOS ships no Mail app, so the old `mailto:` rows in Help & Feedback did
/// nothing at all when a viewer selected them — `UIApplication.open` on a
/// mailto URL is a silent no-op there. This posts to the same
/// `support_request` edge function the website and the phone apps use, so a
/// request raised from the Apple TV lands in `support_requests` with
/// `channel = "app"` and reaches the same triage.
enum TVSupportRequestService {

    /// The topic vocabulary the website support form already uses.
    static let topics = [
        "Something is broken",
        "I have a question",
        "Feature request",
        "Account or billing"
    ]

    static func submit(
        name: String,
        email: String,
        topic: String,
        message: String
    ) async -> Bool {
        let base = TVSupabaseConfig.url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(base)/functions/v1/support_request") else { return false }

        let payload: [String: Any] = [
            "name": name,
            "email": email,
            "topic": topic,
            "message": message,
            "channel": "app",
            "subject": "GuideStream TV (Apple TV) — \(topic)",
            "app_version": appVersion,
            "build": buildNumber,
            "device_model": deviceModel,
            "os_version": "tvOS \(UIDevice.current.systemVersion)",
            "device_id": DeviceIdentity.shared.deviceId
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(TVSupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(TVSupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
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

    /// Hardware identifier ("AppleTV14,1") rather than UIDevice's generic
    /// "Apple TV", so support can tell an HD box from a 4K.
    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) ?? "" }
        }
        return identifier.isEmpty ? "Apple TV" : identifier
    }
}
