//
//  Show.swift
//  GuideStreamTV
//

import SwiftUI

/// Legacy shape used by a handful of unreferenced preview views.
/// All real content is now sourced from TMDB / Watchmode / Supabase.
struct Show: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let network: String
    let episode: String
    let duration: String
    let progress: Double
    let badge: String?
    let posterColors: [Color]
    let symbol: String
    let accent: Color
}
