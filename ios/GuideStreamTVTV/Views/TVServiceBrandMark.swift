//
//  TVServiceBrandMark.swift
//  GuideStreamTVTV
//
//  The brand marks from iPhone's services pill, ported.
//
//  Not TMDB's provider artwork: `provider_brand_map.logo_path` points at
//  JPEGs, which carry no alpha, so any attempt to place one on a dark screen
//  ends as a white square. iPhone never used them — `StreamingServiceViews`
//  draws each service from its own colour and glyph, and this is that data
//  and that rendering, at ten-foot sizes.
//
//  Ported from ios/GuideStreamTV/Models/StreamingService.swift. Keep the two
//  in step: a service added there should be added here.
//

import SwiftUI

enum TVServiceBrandDisplay {
    /// Word-mark or monogram; "\n" breaks the line.
    case text(String, Color, weight: Font.Weight, design: Font.Design)
    /// A single SF Symbol.
    case symbol(String, Color)
    /// SF Symbol plus trailing text — the Apple logo followed by "tv+".
    case symbolText(String, String, Color)
    /// Solid star, for Starz.
    case star
}

struct TVServiceBrand {
    let id: String
    let bg: Color
    let display: TVServiceBrandDisplay
}

enum TVServiceBrandCatalog {
    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    static let all: [TVServiceBrand] = [
        .init(id: "netflix", bg: .black,
              display: .text("N", rgb(0xE5, 0x09, 0x14), weight: .black, design: .serif)),
        .init(id: "prime", bg: rgb(0x1A, 0x20, 0x2C),
              display: .text("prime\nvideo", .white, weight: .bold, design: .default)),
        .init(id: "disney", bg: rgb(0x0E, 0x29, 0x3F),
              display: .text("Disney+", .white, weight: .semibold, design: .serif)),
        .init(id: "hbo", bg: rgb(0x00, 0x1E, 0xE0),
              display: .text("max", .white, weight: .black, design: .default)),
        .init(id: "max", bg: rgb(0x00, 0x1E, 0xE0),
              display: .text("max", .white, weight: .black, design: .default)),
        .init(id: "appletv", bg: .black,
              display: .symbolText("applelogo", "tv+", .white)),
        .init(id: "paramount", bg: rgb(0x00, 0x64, 0xFF),
              display: .text("P+", .white, weight: .black, design: .default)),
        .init(id: "hulu", bg: rgb(0x1C, 0xE7, 0x83),
              display: .text("hulu", .black, weight: .black, design: .rounded)),
        .init(id: "peacock", bg: .black,
              display: .text("peacock", .white, weight: .bold, design: .default)),
        .init(id: "crunchyroll", bg: rgb(0xF4, 0x7B, 0x20),
              display: .text("crunchyroll", .white, weight: .black, design: .rounded)),
        .init(id: "espn", bg: rgb(0x00, 0x1A, 0x70),
              display: .text("ESPN+", .white, weight: .black, design: .default)),
        .init(id: "discovery", bg: rgb(0x00, 0x4D, 0xFA),
              display: .text("d+", .white, weight: .black, design: .rounded)),
        .init(id: "mgm", bg: rgb(0x0A, 0x0A, 0x0A),
              display: .text("MGM+", rgb(0xC7, 0xA1, 0x5A), weight: .black, design: .rounded)),
        .init(id: "starz", bg: rgb(0x14, 0x05, 0x20), display: .star),
        .init(id: "showtime", bg: .black,
              display: .text("SHO", rgb(0xD8, 0x00, 0x00), weight: .black, design: .default)),
        .init(id: "amc", bg: .black,
              display: .text("amc+", .white, weight: .black, design: .default)),
        .init(id: "mubi", bg: .black,
              display: .text("MUBI", .white, weight: .black, design: .default)),
        .init(id: "dazn", bg: .black,
              display: .text("DAZN", rgb(0xF4, 0x00, 0x29), weight: .black, design: .default)),
        .init(id: "youtube", bg: .white,
              display: .symbol("play.rectangle.fill", rgb(0xFF, 0x00, 0x00))),
        .init(id: "youtubetv", bg: .white,
              display: .text("YT TV", rgb(0xFF, 0x00, 0x00), weight: .black, design: .rounded)),
        // Transactional storefronts. They are not in the phone's catalogue —
        // nobody subscribes to them — but they are exactly what the offer
        // sheet lists, so they need marks of their own.
        .init(id: "amazonvideo", bg: rgb(0x1A, 0x20, 0x2C),
              display: .text("prime\nvideo", .white, weight: .bold, design: .default)),
        .init(id: "appletvstore", bg: .black,
              display: .symbolText("applelogo", "tv", .white)),
        .init(id: "fandango", bg: rgb(0xFF, 0x62, 0x00),
              display: .text("fandango", .white, weight: .black, design: .rounded)),
        .init(id: "vudu", bg: rgb(0x00, 0x9E, 0xE0),
              display: .text("vudu", .white, weight: .black, design: .rounded)),
        .init(id: "googleplay", bg: .white,
              display: .symbol("play.fill", rgb(0x1A, 0x73, 0xE8)))
    ]

    static func brand(id: String?) -> TVServiceBrand? {
        guard let id, !id.isEmpty else { return nil }
        let key = id.lowercased()
        return all.first { $0.id == key }
    }

    /// Resolves a Watchmode or TMDB provider name to a brand. Goes through
    /// `Platform.from` first, which knows provider_brand_map's aliases, then
    /// falls back to matching the normalised name against the ids here so the
    /// storefronts above resolve without a catalog_id on the server.
    static func brand(providerName raw: String) -> TVServiceBrand? {
        if let catalogId = Platform.from(providerName: raw)?.catalogId,
           let hit = brand(id: catalogId) {
            return hit
        }
        let normalised = raw.lowercased()
            .replacingOccurrences(of: "plus", with: "+")
            .filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") }
        guard !normalised.isEmpty else { return nil }
        return all.first { normalised.contains($0.id) || $0.id.contains(normalised) }
    }
}

/// Brand mark. `size` is the diameter, or the side of the square when
/// `cornerRadius` is given.
struct TVServiceBrandMark: View {
    let providerName: String
    var size: CGFloat = 52
    /// The exact catalog id, when the caller has one. StreamingCatalog's ids
    /// are this catalog's ids, so matching on it is exact — the name match
    /// below is a heuristic built for TMDB's provider strings and should not
    /// be relied on when the id is already in hand.
    var catalogId: String? = nil
    /// nil draws the circular mark the pills use. A value draws a rounded
    /// square, which is what the services grid needs to match the phone.
    var cornerRadius: CGFloat? = nil

    private var brand: TVServiceBrand? {
        TVServiceBrandCatalog.brand(id: catalogId)
            ?? TVServiceBrandCatalog.brand(providerName: providerName)
    }

    var body: some View {
        if let cornerRadius {
            mark(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            mark(Circle())
        }
    }

    private func mark<S: InsettableShape>(_ shape: S) -> some View {
        shape
            .fill(brand?.bg ?? Color(white: 0.16))
            .frame(width: size, height: size)
            .overlay { content.padding(size * 0.14) }
            .overlay(shape.stroke(.white.opacity(0.22), lineWidth: 1))
            .clipShape(shape)
    }

    @ViewBuilder
    private var content: some View {
        switch brand?.display {
        case .text(let str, let color, let weight, let design):
            Text(str)
                .font(.system(size: textSize(for: str), weight: weight, design: design))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .lineLimit(2)
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(color)
        case .symbolText(let symbol, let suffix, let color):
            HStack(spacing: size * 0.03) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.34, weight: .bold))
                Text(suffix)
                    .font(.system(size: size * 0.28, weight: .bold))
            }
            .foregroundStyle(color)
        case .star:
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(Color(red: 0xFF / 255, green: 0xC8 / 255, blue: 0x1E / 255))
        case nil:
            // No brand on file: initials, so the mark still identifies the
            // service rather than showing an empty disc.
            Text(fallbackInitials)
                .font(.system(size: size * 0.34, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private var fallbackInitials: String {
        let words = providerName.split(separator: " ")
        let initials = words.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return providerName.contains("+") ? String(initials.prefix(1)) + "+" : initials.uppercased()
    }

    /// Short monograms take the space; long word-marks shrink. Same heuristic
    /// as the phone's `textSize(for:)`, scaled to the diameter.
    private func textSize(for str: String) -> CGFloat {
        if str.count <= 1 { return size * 0.55 }
        if str.count <= 3 { return size * 0.42 }
        if str.contains("\n") { return size * 0.26 }
        if str.count <= 5 { return size * 0.30 }
        return size * 0.22
    }
}
