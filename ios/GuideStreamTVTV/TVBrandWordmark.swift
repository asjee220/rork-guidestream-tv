//
//  TVBrandWordmark.swift
//  GuideStreamTVTV
//
//  tvOS counterpart of the phone app's BrandWordmark. Renders as live text
//  rather than an image asset so the wordmark stays sharp at 4K and scales
//  cleanly across hero, large, and nav sizes. Mirrors the phone wordmark's
//  lighter-blue "TV" superscript — see the literal color values below.
//

import SwiftUI

struct TVBrandWordmark: View {
    public enum TVWordmarkSize {
        case hero
        case large
        case nav

        var baseSize: CGFloat {
            switch self {
            case .hero: return 140
            case .large: return 88
            case .nav: return 40
            }
        }

        var tvSize: CGFloat {
            switch self {
            case .hero: return 76
            case .large: return 48
            case .nav: return 22
            }
        }

        var weight: Font.Weight {
            switch self {
            case .hero: return .heavy
            case .large: return .heavy
            case .nav: return .heavy
            }
        }
    }

    var wordmarkSize: TVWordmarkSize = .large

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Guide")
                .scaledFont(size: wordmarkSize.baseSize, weight: wordmarkSize.weight)
                .foregroundStyle(.white)
            Text("Stream")
                .scaledFont(size: wordmarkSize.baseSize, weight: wordmarkSize.weight)
                .foregroundStyle(Color(red: 0xF5 / 255, green: 0x82 / 255, blue: 0x1F / 255))
            Text("TV")
                .scaledFont(size: wordmarkSize.tvSize, weight: .bold)
                .foregroundStyle(Color(red: 0x5B / 255, green: 0xB0 / 255, blue: 0xFF / 255))
                .baselineOffset(wordmarkSize.baseSize * 0.30)
                .padding(.leading, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("GuideStream TV")
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
