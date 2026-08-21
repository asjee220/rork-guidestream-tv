//
//  ShareService.swift
//  GuideStreamTV
//

import SwiftUI
import UIKit

/// The entity a share link points at. Determines the `/w/{segment}` path
/// segment of the canonical share URL.
enum ShareKind {
    case movie
    case tv
    case creator
    case game

    var segment: String {
        switch self {
        case .movie: return "movie"
        case .tv: return "tv"
        case .creator: return "c"
        case .game: return "g"
        }
    }
}

/// Single source of truth for every share affordance in the app so all
/// surfaces produce the same `https://guidestream.tv/w/{segment}/{id}?t={title}`
/// deep-link format.
enum ShareService {
    /// Builds the canonical GuideStream share URL. The id is percent-encoded
    /// for the path (so ids containing colons such as `yt:UC123` survive) and
    /// the title for the query. A blank title falls back to the id. Returns
    /// the bare site URL when construction fails.
    static func shareURL(kind: ShareKind, id: String, title: String) -> URL {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = trimmedTitle.isEmpty ? id : trimmedTitle
        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let encodedTitle = effectiveTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? effectiveTitle
        let urlString = "https://guidestream.tv/w/\(kind.segment)/\(encodedId)?t=\(encodedTitle)"
        return URL(string: urlString) ?? URL(string: "https://guidestream.tv")!
    }

    /// Message shared alongside the URL.
    static func shareMessage(title: String) -> String {
        "Watch \(title) on GuideStream TV"
    }
}

/// UIKit share sheet wrapper so state-driven `.sheet` presentation can hand
/// arbitrary items (URL + message) to the system activity controller.
struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
