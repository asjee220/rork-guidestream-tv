//
//  InAppBrowserPresenter.swift
//  GuideStreamTV
//
//  Presents a web page in an SFSafariViewController sheet from code that has
//  no SwiftUI view to hang a `.sheet(item:)` on.
//
//  `Views/InAppBrowser.swift` (GUI-87) is the SwiftUI wrapper used by Help &
//  Feedback, the legal rows and onboarding consent. This is the same
//  controller with the same brand chrome, presented imperatively, because the
//  deep-link chain in `StreamingDeepLinker` is a set of fire-and-forget
//  statics with no view in scope. Two entry points, one behaviour — keep the
//  configuration here in step with `SafariView`.
//
//  Why SFSafariViewController and not a chromeless WKWebView: the Safari
//  controller shares cookies and storage with Safari itself, so a viewer
//  already signed in to the service lands on the title page signed in, and an
//  affiliate click survives into a conversion completed later in Safari. A
//  WKWebView has its own jar — it would present a sign-in wall to someone who
//  is already a subscriber, and drop the attribution.
//

import SafariServices
import SwiftUI
import UIKit

@MainActor
enum InAppBrowserPresenter {

    /// Presents `url` over whatever is currently on screen.
    ///
    /// Returns `false` when the URL is not http(s) — SFSafariViewController
    /// requires that — or when no window is available. Callers must handle
    /// that case rather than assume the page was shown.
    @discardableResult
    static func present(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else {
            print("[InAppBrowser] refusing non-web scheme: \(url.absoluteString)")
            return false
        }
        guard let presenter = topViewController() else {
            print("[InAppBrowser] no window to present from")
            return false
        }

        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredBarTintColor = UIColor(Color.navy)
        controller.preferredControlTintColor = UIColor(Color.orange)
        controller.dismissButtonStyle = .close

        presenter.present(controller, animated: true)
        return true
    }

    /// Walks to the top-most presented controller, **skipping anything that is
    /// already being dismissed**. Watch buttons live inside sheets that start
    /// closing on the same tap; presenting onto a controller mid-dismiss is
    /// silently dropped, which is the same class of bug as the open-during-
    /// dismiss race `StreamingDeepLinker.openResolvedURL` exists to avoid.
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
