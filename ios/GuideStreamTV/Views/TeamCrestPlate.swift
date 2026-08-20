//
//  TeamCrestPlate.swift
//  GuideStreamTV
//

import SwiftUI

/// Shared neutral light plate behind a team crest. ESPN serves crests on
/// transparent backgrounds, so the old 7% team-colour plate made dark-primary
/// crests (navy, black) disappear against the near-black card; a near-white
/// plate keeps every crest legible regardless of the team's primary colour.
/// The abbreviation fallback badge is intentionally separate — it fills with
/// the full team colour and white text.
struct TeamCrestPlate: View {
    let size: CGFloat
    let cornerRadius: CGFloat
    let inset: CGFloat
    let image: Image

    /// Neutral light fill shared by every crest render site.
    static let fillColor = Color.white.opacity(0.92)

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Self.fillColor)
            .frame(width: size, height: size)
            .overlay {
                image
                    .resizable()
                    .scaledToFit()
                    .padding(inset)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
