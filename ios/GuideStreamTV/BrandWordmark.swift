//
//  BrandWordmark.swift
//  GuideStreamTV
//

import SwiftUI

public struct BrandWordmark: View {
    public enum WordmarkSize {
        case large
        case nav
        case small

        var baseSize: CGFloat {
            switch self {
            case .large: return 36
            case .nav: return 18
            case .small: return 13
            }
        }

        var tvSize: CGFloat {
            switch self {
            case .large: return 20
            case .nav: return 11
            case .small: return 8
            }
        }

        var weight: Font.Weight {
            switch self {
            case .large: return .heavy
            case .nav: return .bold
            case .small: return .semibold
            }
        }
    }

    var wordmarkSize: WordmarkSize = .nav

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Guide")
                .scaledFont(size: wordmarkSize.baseSize, weight: wordmarkSize.weight)
                .foregroundStyle(.white)
            Text("Stream")
                .scaledFont(size: wordmarkSize.baseSize, weight: wordmarkSize.weight)
                .foregroundStyle(Color(red: 0xF5 / 255, green: 0x82 / 255, blue: 0x1F / 255))
            Text(" TV")
                .scaledFont(size: wordmarkSize.tvSize, weight: wordmarkSize.weight)
                .foregroundStyle(Color(red: 0x5B / 255, green: 0xB0 / 255, blue: 0xFF / 255))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("GuideStream TV")
    }
}
