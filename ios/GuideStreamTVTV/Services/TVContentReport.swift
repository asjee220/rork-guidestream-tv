//
//  TVContentReport.swift
//  GuideStreamTVTV
//
//  In-app "Report a problem" (30 Sep 2026) — same model and endpoint as the
//  iOS ContentReportService.swift, for this target. Reports post to the
//  content_report edge function (verify_jwt = false); DeepLinkReturnCheck is
//  the "Did it open?" sampling (4 s – 20 min away, at most once per 12 h).
//

import Foundation
import Supabase

enum ContentReportKind: String {
    case title
    case sports
}

enum ReportReason: String, CaseIterable, Identifiable {
    case wrongService = "wrong_service"
    case linkBroken = "link_broken"
    case unavailable = "unavailable"
    case wrongPrice = "wrong_price"
    case wrongDetails = "wrong_details"
    case wrongChannel = "wrong_channel"
    case wrongTime = "wrong_time"
    case other = "other"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wrongService: return String(localized: "Wrong streaming service")
        case .linkBroken: return String(localized: "Button didn’t open it")
        case .unavailable: return String(localized: "No longer available here")
        case .wrongPrice: return String(localized: "Wrong price or plan (free / paid)")
        case .wrongDetails: return String(localized: "Wrong details or artwork")
        case .wrongChannel: return String(localized: "Wrong channel or service")
        case .wrongTime: return String(localized: "Wrong start time")
        case .other: return String(localized: "Something else")
        }
    }

    static func options(for kind: ContentReportKind) -> [ReportReason] {
        switch kind {
        case .title: return [.wrongService, .linkBroken, .unavailable, .wrongPrice, .wrongDetails, .other]
        case .sports: return [.wrongChannel, .wrongTime, .linkBroken, .other]
        }
    }
}

struct ReportContext: Identifiable {
    let id = UUID()
    var kind: ContentReportKind = .title
    /// detail_link | deeplink_return | sports_link
    var entryPoint: String
    var titleName: String
    var providerName: String?
    var titleId: String?
    var tmdbId: Int?
    var isTV: Bool?
    var gameId: String?
    var preselected: ReportReason?
}

enum ContentReportService {
    static let platform = "tvos"

    static func submit(_ context: ReportContext, reason: ReportReason, note: String) async -> Bool {
        let base = TVSupabaseConfig.url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(base)/functions/v1/content_report") else { return false }
        let userId = await MainActor.run { AuthViewModel.shared.currentUser?.id.uuidString }
        let deviceId = await MainActor.run { DeviceIdentity.shared.deviceId }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        var payload: [String: Any] = [
            "kind": context.kind.rawValue,
            "entry_point": context.entryPoint,
            "reason": reason.rawValue,
            "title_name": context.titleName,
            "region": DeviceLocale.current().region,
            "platform": platform,
            "app_version": version,
            "device_id": deviceId
        ]
        if let v = context.providerName, !v.isEmpty { payload["provider_name"] = v }
        if let v = context.titleId { payload["title_id"] = v }
        if let v = context.tmdbId { payload["tmdb_id"] = v }
        if let v = context.isTV { payload["media_type"] = v ? "tv" : "movie" }
        if let v = context.gameId { payload["game_id"] = v }
        if let userId { payload["user_id"] = userId }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { payload["note"] = trimmed }

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
}

/// "Did <service> open <title>?" — armed on an outbound watch launch, offered
/// by the screen that launched it when the viewer comes back.
@MainActor
final class DeepLinkReturnCheck {
    static let shared = DeepLinkReturnCheck()
    private init() {}

    struct Pending: Identifiable {
        let id = UUID()
        let title: String
        let platform: String
        let tmdbId: Int?
        let titleId: String?
        let gameId: String?
        let armedAt: Date

        var reportContext: ReportContext {
            ReportContext(
                kind: gameId == nil ? .title : .sports,
                entryPoint: "deeplink_return",
                titleName: title,
                providerName: platform,
                titleId: titleId,
                tmdbId: tmdbId,
                gameId: gameId,
                preselected: .linkBroken
            )
        }
    }

    private var pending: Pending?
    private var leftApp = false
    private let lastShownKey = "gs.deeplinkReturnCheck.lastShown"

    func arm(title: String, platform: String, tmdbId: Int?, titleId: String?, gameId: String? = nil) {
        let p = platform.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, !title.isEmpty else { return }
        pending = Pending(title: title, platform: p, tmdbId: tmdbId, titleId: titleId, gameId: gameId, armedAt: Date())
        leftApp = false
    }

    func noteLeft() {
        if pending != nil { leftApp = true }
    }

    /// The prompt to show on this return, or nil. Clears the armed launch.
    func consumeOnReturn() -> Pending? {
        guard let p = pending else { return nil }
        let elapsed = Date().timeIntervalSince(p.armedAt)
        guard leftApp else {
            if elapsed > 20 * 60 { pending = nil }
            return nil
        }
        pending = nil
        leftApp = false
        guard elapsed >= 4, elapsed <= 20 * 60 else { return nil }
        let defaults = UserDefaults.standard
        guard Date().timeIntervalSince1970 - defaults.double(forKey: lastShownKey) >= 12 * 60 * 60 else { return nil }
        defaults.set(Date().timeIntervalSince1970, forKey: lastShownKey)
        return p
    }

    func record(_ p: Pending, opened: Bool) {
        WatchIntentLogger.shared.log(
            eventType: opened ? .deeplinkConfirmed : .deeplinkFailed,
            titleId: p.titleId ?? p.tmdbId.map(String.init) ?? WatchIntentLogger.titleSlug(p.title),
            platformId: p.platform,
            metadata: [
                "platform_name": p.platform,
                "tmdb_id": p.tmdbId.map(String.init) ?? "",
                "game_id": p.gameId ?? "",
                "seconds_away": Int(Date().timeIntervalSince(p.armedAt))
            ]
        )
    }
}
