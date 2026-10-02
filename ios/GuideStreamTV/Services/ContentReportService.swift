//
//  ContentReportService.swift
//  GuideStreamTV
//
//  In-app "Report a problem" (30 Sep 2026). Three entry points share one
//  sheet and one endpoint:
//
//  * A — the "Wrong service or link? Report it" line under Where to Watch on
//    the episode detail sheet and the full show detail screen.
//  * C — `DeepLinkReturnCheck`: on return from a streaming app, a small card
//    asks whether the title opened. Answers land in watch_intent_events as
//    deeplink_confirmed / deeplink_failed; "No" opens the report sheet.
//  * D — "Wrong channel or time?" under the Watch CTA in SportsWatchSheet.
//
//  Reports post to the `content_report` edge function (verify_jwt = false,
//  same pattern as SupportRequestService), which writes content_reports with
//  the service role and re-checks Watchmode for source complaints.
//

import Foundation
import SwiftUI
import UIKit
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

struct ReportContext {
    var kind: ContentReportKind = .title
    /// detail_link | deeplink_return | sports_link — must match the
    /// content_reports.entry_point check constraint.
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

    /// Returns true only on a 2xx, so the sheet can keep the user's input on
    /// screen for a retry.
    static func submit(_ context: ReportContext, reason: ReportReason, note: String) async -> Bool {
        let base = SupabaseConfig.url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(base)/functions/v1/content_report") else { return false }

        let userId = await MainActor.run { AuthViewModel.shared.currentUser?.id.uuidString }
        let deviceId = await MainActor.run { DeviceIdentity.shared.deviceId }

        var payload: [String: Any] = [
            "kind": context.kind.rawValue,
            "entry_point": context.entryPoint,
            "reason": reason.rawValue,
            "title_name": context.titleName,
            "region": DeviceLocale.current().region,
            "platform": "ios",
            "app_version": SupportRequestService.appVersion,
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
}

/// Presents the report UI from UIKit, on top of whatever is showing — the
/// entry points live inside sheets, and the return check fires from the app
/// root while a sheet may still be up.
@MainActor
enum ReportPresenter {

    static func presentReport(_ context: ReportContext) {
        guard let top = topViewController() else { return }
        var host: UIHostingController<ReportProblemSheet>!
        host = UIHostingController(rootView: ReportProblemSheet(context: context, onClose: {
            host?.dismiss(animated: true)
        }))
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = UIColor(Color.navy)
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
        top.present(host, animated: true)
    }

    static func presentReturnCheck(_ pending: DeepLinkReturnCheck.Pending) {
        guard let top = topViewController() else { return }
        var host: UIHostingController<DeepLinkReturnCard>!
        host = UIHostingController(rootView: DeepLinkReturnCard(
            pending: pending,
            onYes: {
                DeepLinkReturnCheck.shared.record(pending, opened: true)
                host?.dismiss(animated: true)
            },
            onNo: {
                DeepLinkReturnCheck.shared.record(pending, opened: false)
                host?.dismiss(animated: true) {
                    presentReport(pending.reportContext)
                }
            },
            onDismiss: { host?.dismiss(animated: true) }
        ))
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = UIColor(Color.navy)
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.custom(identifier: .init("gs.returnCheck")) { _ in 210 }]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
        top.present(host, animated: true)
    }

    /// Top-most controller, skipping anything already being dismissed (same
    /// walk as InAppBrowserPresenter).
    private static func topViewController() -> UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow)?.rootViewController }
            .first
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

/// C — "Did <service> open <title>?" on return from a deep link.
///
/// Armed by StreamingDeepLinker on every outbound open. Shown only when the
/// app actually went to the background and ReturnCheckPolicy says to ask.
@MainActor
final class DeepLinkReturnCheck {
    static let shared = DeepLinkReturnCheck()
    private init() {}

    struct Pending {
        let title: String
        let platform: String
        let tmdbId: Int?
        let titleSlug: String?
        let gameId: String?
        let armedAt: Date

        var reportContext: ReportContext {
            ReportContext(
                kind: gameId == nil ? .title : .sports,
                entryPoint: "deeplink_return",
                titleName: title,
                providerName: platform,
                titleId: titleSlug ?? tmdbId.map(String.init),
                tmdbId: tmdbId,
                isTV: nil,
                gameId: gameId,
                preselected: .linkBroken
            )
        }
    }

    private var pending: Pending?
    private var leftApp = false

    func arm(title: String, platform: String, tmdbId: Int?, titleSlug: String?, gameId: String? = nil) {
        let p = platform.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, !title.isEmpty else { return }
        pending = Pending(title: title, platform: p, tmdbId: tmdbId, titleSlug: titleSlug, gameId: gameId, armedAt: Date())
        leftApp = false
        ReturnCheckPolicy.refreshFlags()
    }

    func noteBackgrounded() {
        if pending != nil { leftApp = true }
    }

    /// Returns true when the card is being shown, so the caller can hold back
    /// other return-time prompts (the in-app review request) for this return.
    @discardableResult
    func appDidBecomeActive() -> Bool {
        guard let p = pending else { return false }
        let elapsed = Date().timeIntervalSince(p.armedAt)
        guard leftApp else {
            if elapsed > 20 * 60 { pending = nil }
            return false
        }
        pending = nil
        leftApp = false
        switch ReturnCheckPolicy.decide(platform: p.platform, tmdbId: p.tmdbId, elapsed: elapsed) {
        case .quickReturn:
            log(p, .deeplinkQuickReturn)
            return false
        case .skip:
            return false
        case .ask:
            break
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            ReportPresenter.presentReturnCheck(p)
        }
        return true
    }

    func record(_ p: Pending, opened: Bool) {
        log(p, opened ? .deeplinkConfirmed : .deeplinkFailed)
    }

    private func log(_ p: Pending, _ type: IntentEventType) {
        WatchIntentLogger.shared.log(
            eventType: type,
            titleId: p.titleSlug ?? p.tmdbId.map(String.init) ?? WatchIntentLogger.titleSlug(p.title),
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

/// Who gets asked "Did it open?" (set 1 Oct 2026, replaces "any return 12h
/// after the last card"):
///  * the first 2 returns from each service ask,
///  * after that about 1 return in 10 asks,
///  * never more than once a day,
///  * a service or title under suspicion — recent health alert, open link
///    report, fresh correction (`get_return_check_flags`) — always asks, at
///    most every 4 hours,
///  * a return under 3 seconds never asks; it is logged as
///    deeplink_quick_return, which the "didn't open" health alert ignores.
@MainActor
enum ReturnCheckPolicy {
    enum Decision { case ask, quickReturn, skip }

    private static let introPerService = 2
    private static let sampleRate = 0.1
    private static let minInterval: TimeInterval = 24 * 60 * 60
    private static let suspectInterval: TimeInterval = 4 * 60 * 60
    private static let quickReturn: TimeInterval = 3
    private static let maxAway: TimeInterval = 20 * 60
    private static let lastShownKey = "gs.deeplinkReturnCheck.lastShown"
    private static let countsKey = "gs.deeplinkReturnCheck.shownByService"

    private static var flagProviders: Set<String> = []
    private static var flagTitles: Set<String> = []
    private static var flagsFetchedAt: Date?

    /// Called on arm, so the list is fresh by the time the viewer returns.
    /// At most one fetch every 30 minutes; a failed fetch retries next arm.
    static func refreshFlags() {
        if let t = flagsFetchedAt, Date().timeIntervalSince(t) < 30 * 60 { return }
        flagsFetchedAt = Date()
        Task {
            struct Flags: Decodable { let providers: [String]; let titles: [String] }
            do {
                let f: Flags = try await SupabaseManager.shared.client
                    .rpc("get_return_check_flags")
                    .execute()
                    .value
                flagProviders = Set(f.providers)
                flagTitles = Set(f.titles)
            } catch {
                flagsFetchedAt = nil
            }
        }
    }

    static func decide(platform: String, tmdbId: Int?, elapsed: TimeInterval) -> Decision {
        if elapsed < quickReturn { return .quickReturn }
        guard elapsed <= maxAway else { return .skip }
        let key = platform.lowercased()
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let sinceLast = now - defaults.double(forKey: lastShownKey)
        let suspect = flagProviders.contains(key)
            || (tmdbId.map { flagTitles.contains("\($0)|\(key)") } ?? false)
        var counts = defaults.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
        let shown = counts[key] ?? 0
        let ask = suspect
            ? sinceLast >= suspectInterval
            : sinceLast >= minInterval && (shown < introPerService || Double.random(in: 0..<1) < sampleRate)
        guard ask else { return .skip }
        defaults.set(now, forKey: lastShownKey)
        counts[key] = shown + 1
        defaults.set(counts, forKey: countsKey)
        return .ask
    }
}
