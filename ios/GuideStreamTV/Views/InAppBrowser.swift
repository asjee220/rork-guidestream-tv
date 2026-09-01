//
//  InAppBrowser.swift
//  GuideStreamTV
//
//  GUI-87 — help and legal links open inside the app.
//

import SafariServices
import SwiftUI

/// Wraps `SFSafariViewController` so a web page can be presented as a sheet
/// over the app instead of task-switching to Safari.
///
/// Used for the Privacy Policy, Terms of Service and YouTube Terms rows in
/// Help & Feedback. The reader chrome is tinted to the brand navy/orange so
/// the page reads as part of GuideStream, and reader/collapsing are left on
/// so long legal pages stay comfortable.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredBarTintColor = UIColor(Color.navy)
        controller.preferredControlTintColor = UIColor(Color.orange)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// A URL wrapped for `.sheet(item:)`, which needs an `Identifiable` payload.
struct InAppBrowserLink: Identifiable {
    let id = UUID()
    let url: URL
}
