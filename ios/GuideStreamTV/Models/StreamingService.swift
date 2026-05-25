//
//  StreamingService.swift
//  GuideStreamTV
//
//  Canonical catalogue of the top ~50 worldwide streaming services. Used by
//  the onboarding "Which services do you have?" grid and the services pill
//  bottom sheet so both surfaces stay in sync. Each entry has a stable `id`
//  (persisted in UserDefaults), a human display name, brand colours, and a
//  visual treatment used to render the tile / mini-icon.
//

import SwiftUI

/// Tile/icon visual treatment for a streaming brand. Keeping the rendering
/// data here lets the same struct power the big onboarding tiles AND the
/// little stacked icons inside the header pill.
enum StreamingServiceDisplay {
    /// Word-mark / monogram. Optional manual line breaks via `\n`.
    case text(String, Color, fontWeight: Font.Weight, design: Font.Design)
    /// Single SF Symbol (e.g. Apple TV+).
    case symbol(String, Color)
    /// SF Symbol + trailing text (e.g. "tv+" after the Apple logo).
    case symbolText(String, String, Color)
    /// Solid star fill (used for Starz).
    case star
}

struct StreamingService: Identifiable, Hashable {
    let id: String
    let name: String
    let bg: Color
    let glow: Color
    let display: StreamingServiceDisplay

    static func == (lhs: StreamingService, rhs: StreamingService) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum StreamingCatalog {
    /// Top 50 streaming services worldwide. Ordering roughly mirrors global
    /// subscriber counts so the most relevant tiles appear first.
    static let all: [StreamingService] = [
        // MARK: - Global / US giants (1–15)
        .init(id: "netflix", name: "Netflix",
              bg: .black,
              glow: Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255),
              display: .text("N", Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255),
                             fontWeight: .black, design: .serif)),
        .init(id: "prime", name: "Prime Video",
              bg: Color(red: 0x1A/255, green: 0x20/255, blue: 0x2C/255),
              glow: Color(red: 0x00/255, green: 0xA8/255, blue: 0xE1/255),
              display: .text("prime\nvideo", Color.white, fontWeight: .bold, design: .default)),
        .init(id: "disney", name: "Disney+",
              bg: Color(red: 0x0E/255, green: 0x29/255, blue: 0x3F/255),
              glow: Color(red: 0x11/255, green: 0x3C/255, blue: 0xCF/255),
              display: .text("Disney+", Color.white, fontWeight: .semibold, design: .serif)),
        .init(id: "hbo", name: "Max",
              bg: Color(red: 0x00/255, green: 0x1E/255, blue: 0xE0/255),
              glow: Color(red: 0x00/255, green: 0x55/255, blue: 0xFF/255),
              display: .text("max", Color.white, fontWeight: .black, design: .default)),
        .init(id: "hulu", name: "Hulu",
              bg: Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255),
              glow: Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255),
              display: .text("hulu", Color.black, fontWeight: .black, design: .rounded)),
        .init(id: "appletv", name: "Apple TV+",
              bg: .black, glow: Color.white,
              display: .symbolText("applelogo", "tv+", Color.white)),
        .init(id: "paramount", name: "Paramount+",
              bg: Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255),
              glow: Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255),
              display: .text("P+", Color.white, fontWeight: .black, design: .default)),
        .init(id: "peacock", name: "Peacock",
              bg: .black,
              glow: Color(red: 0xFF/255, green: 0x66/255, blue: 0x00/255),
              display: .text("peacock", Color.white, fontWeight: .bold, design: .default)),
        .init(id: "crunchyroll", name: "Crunchyroll",
              bg: Color(red: 0xF4/255, green: 0x7B/255, blue: 0x20/255),
              glow: Color(red: 0xF4/255, green: 0x7B/255, blue: 0x20/255),
              display: .text("crunchyroll", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "starz", name: "Starz",
              bg: Color(red: 0x14/255, green: 0x05/255, blue: 0x20/255),
              glow: Color(red: 0xFF/255, green: 0xC8/255, blue: 0x1E/255),
              display: .star),
        .init(id: "showtime", name: "Showtime",
              bg: .black,
              glow: Color(red: 0xD8/255, green: 0x00/255, blue: 0x00/255),
              display: .text("SHO", Color(red: 0xD8/255, green: 0x00/255, blue: 0x00/255),
                             fontWeight: .black, design: .default)),
        .init(id: "amc", name: "AMC+",
              bg: .black,
              glow: Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255),
              display: .text("amc+", Color.white, fontWeight: .black, design: .default)),
        .init(id: "espn", name: "ESPN+",
              bg: Color(red: 0x00/255, green: 0x1A/255, blue: 0x70/255),
              glow: Color(red: 0xD0/255, green: 0x21/255, blue: 0x31/255),
              display: .text("ESPN+", Color.white, fontWeight: .black, design: .default)),
        .init(id: "discovery", name: "Discovery+",
              bg: Color(red: 0x00/255, green: 0x4D/255, blue: 0xFA/255),
              glow: Color(red: 0x00/255, green: 0x9A/255, blue: 0xFF/255),
              display: .text("d+", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "youtube", name: "YouTube",
              bg: .black,
              glow: Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255),
              display: .symbol("play.rectangle.fill", Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255))),

        // MARK: - US/Free + niche (16–26)
        .init(id: "tubi", name: "Tubi",
              bg: Color(red: 0xD3/255, green: 0x14/255, blue: 0x21/255),
              glow: Color(red: 0xFF/255, green: 0x40/255, blue: 0x40/255),
              display: .text("tubi", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "pluto", name: "Pluto TV",
              bg: Color(red: 0x18/255, green: 0x10/255, blue: 0x37/255),
              glow: Color(red: 0xFF/255, green: 0xE0/255, blue: 0x36/255),
              display: .text("Pluto", Color(red: 0xFF/255, green: 0xE0/255, blue: 0x36/255),
                             fontWeight: .black, design: .rounded)),
        .init(id: "roku", name: "Roku Channel",
              bg: Color(red: 0x66/255, green: 0x2D/255, blue: 0x91/255),
              glow: Color(red: 0xB4/255, green: 0x53/255, blue: 0xFF/255),
              display: .text("Roku", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "plex", name: "Plex",
              bg: .black,
              glow: Color(red: 0xE5/255, green: 0xA0/255, blue: 0x17/255),
              display: .symbol("play.tv.fill", Color(red: 0xE5/255, green: 0xA0/255, blue: 0x17/255))),
        .init(id: "crackle", name: "Crackle",
              bg: .black,
              glow: Color(red: 0xFF/255, green: 0xA8/255, blue: 0x00/255),
              display: .text("crackle", Color(red: 0xFF/255, green: 0xA8/255, blue: 0x00/255),
                             fontWeight: .black, design: .rounded)),
        .init(id: "mubi", name: "Mubi",
              bg: .black, glow: Color.white,
              display: .text("MUBI", Color.white, fontWeight: .black, design: .default)),
        .init(id: "fubo", name: "Fubo",
              bg: Color(red: 0xEC/255, green: 0x18/255, blue: 0x40/255),
              glow: Color(red: 0xEC/255, green: 0x18/255, blue: 0x40/255),
              display: .text("fubo", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "sling", name: "Sling TV",
              bg: .black,
              glow: Color(red: 0xFF/255, green: 0x73/255, blue: 0x00/255),
              display: .text("sling", Color(red: 0xFF/255, green: 0x73/255, blue: 0x00/255),
                             fontWeight: .black, design: .rounded)),
        .init(id: "youtubetv", name: "YouTube TV",
              bg: .white,
              glow: Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255),
              display: .text("YT TV", Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255),
                             fontWeight: .black, design: .rounded)),
        .init(id: "dazn", name: "DAZN",
              bg: .black,
              glow: Color(red: 0xF4/255, green: 0x00/255, blue: 0x29/255),
              display: .text("DAZN", Color(red: 0xF4/255, green: 0x00/255, blue: 0x29/255),
                             fontWeight: .black, design: .default)),
        .init(id: "shudder", name: "Shudder",
              bg: .black,
              glow: Color(red: 0x9A/255, green: 0x00/255, blue: 0xFF/255),
              display: .text("shudder", Color(red: 0x9A/255, green: 0x00/255, blue: 0xFF/255),
                             fontWeight: .black, design: .rounded)),
        .init(id: "curiosity", name: "Curiosity",
              bg: Color(red: 0x0A/255, green: 0x12/255, blue: 0x2A/255),
              glow: Color(red: 0x00/255, green: 0xC2/255, blue: 0xFF/255),
              display: .text("CS", Color(red: 0x00/255, green: 0xC2/255, blue: 0xFF/255),
                             fontWeight: .black, design: .default)),

        // MARK: - UK (27–32)
        .init(id: "bbciplayer", name: "BBC iPlayer",
              bg: .black,
              glow: Color(red: 0xFB/255, green: 0xB0/255, blue: 0x32/255),
              display: .text("iPlayer", Color(red: 0xFB/255, green: 0xB0/255, blue: 0x32/255),
                             fontWeight: .black, design: .default)),
        .init(id: "itvx", name: "ITVX",
              bg: .black,
              glow: Color(red: 0xFF/255, green: 0xC0/255, blue: 0x00/255),
              display: .text("ITVX", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "channel4", name: "Channel 4",
              bg: .black,
              glow: Color(red: 0xAA/255, green: 0xFF/255, blue: 0x00/255),
              display: .text("4", Color(red: 0xAA/255, green: 0xFF/255, blue: 0x00/255),
                             fontWeight: .black, design: .rounded)),
        .init(id: "nowtv", name: "NOW",
              bg: Color(red: 0x00/255, green: 0x55/255, blue: 0xA4/255),
              glow: Color(red: 0x00/255, green: 0xB7/255, blue: 0xFF/255),
              display: .text("NOW", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "britbox", name: "BritBox",
              bg: Color(red: 0x12/255, green: 0x33/255, blue: 0x9C/255),
              glow: Color(red: 0xFF/255, green: 0x4B/255, blue: 0x9C/255),
              display: .text("Brit\nBox", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "acorntv", name: "Acorn TV",
              bg: Color(red: 0x21/255, green: 0x47/255, blue: 0x2A/255),
              glow: Color(red: 0x6E/255, green: 0xC1/255, blue: 0x6E/255),
              display: .text("Acorn", Color.white, fontWeight: .black, design: .serif)),

        // MARK: - Europe / Australia / LATAM (33–41)
        .init(id: "canalplus", name: "Canal+",
              bg: .black, glow: Color.white,
              display: .text("CANAL+", Color.white, fontWeight: .black, design: .default)),
        .init(id: "skyshowtime", name: "SkyShowtime",
              bg: .black,
              glow: Color(red: 0xFF/255, green: 0x00/255, blue: 0x73/255),
              display: .text("S+", Color(red: 0xFF/255, green: 0x00/255, blue: 0x73/255),
                             fontWeight: .black, design: .default)),
        .init(id: "raiplay", name: "RaiPlay",
              bg: Color(red: 0x00/255, green: 0x47/255, blue: 0xC8/255),
              glow: Color(red: 0x00/255, green: 0xB7/255, blue: 0xFF/255),
              display: .text("Rai\nPlay", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "stan", name: "Stan",
              bg: .black,
              glow: Color(red: 0x00/255, green: 0xD4/255, blue: 0xFF/255),
              display: .text("stan.", Color(red: 0x00/255, green: 0xD4/255, blue: 0xFF/255),
                             fontWeight: .black, design: .rounded)),
        .init(id: "binge", name: "Binge",
              bg: Color(red: 0xFF/255, green: 0x29/255, blue: 0x00/255),
              glow: Color(red: 0xFF/255, green: 0x29/255, blue: 0x00/255),
              display: .text("binge", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "kayo", name: "Kayo Sports",
              bg: .black,
              glow: Color(red: 0x18/255, green: 0xE0/255, blue: 0xC8/255),
              display: .text("Kayo", Color(red: 0x18/255, green: 0xE0/255, blue: 0xC8/255),
                             fontWeight: .black, design: .rounded)),
        .init(id: "globoplay", name: "Globoplay",
              bg: .black,
              glow: Color(red: 0xFF/255, green: 0x29/255, blue: 0x66/255),
              display: .text("globo\nplay", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "vix", name: "ViX",
              bg: Color(red: 0xFF/255, green: 0x29/255, blue: 0x00/255),
              glow: Color(red: 0xFF/255, green: 0xC0/255, blue: 0x00/255),
              display: .text("ViX", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "rakutenviki", name: "Viki",
              bg: Color(red: 0x16/255, green: 0x18/255, blue: 0x29/255),
              glow: Color(red: 0xBC/255, green: 0x00/255, blue: 0x6C/255),
              display: .text("VIKI", Color(red: 0xBC/255, green: 0x00/255, blue: 0x6C/255),
                             fontWeight: .black, design: .default)),

        // MARK: - India (42–45)
        .init(id: "hotstar", name: "Hotstar",
              bg: Color(red: 0x0A/255, green: 0x11/255, blue: 0x2E/255),
              glow: Color(red: 0x18/255, green: 0x47/255, blue: 0xFF/255),
              display: .text("hotstar", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "jiocinema", name: "JioCinema",
              bg: Color(red: 0xE4/255, green: 0x1F/255, blue: 0x1F/255),
              glow: Color(red: 0xFF/255, green: 0x60/255, blue: 0x33/255),
              display: .text("Jio", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "sonyliv", name: "SonyLIV",
              bg: .black,
              glow: Color(red: 0xFF/255, green: 0x66/255, blue: 0x00/255),
              display: .text("LIV", Color(red: 0xFF/255, green: 0x66/255, blue: 0x00/255),
                             fontWeight: .black, design: .default)),
        .init(id: "zee5", name: "Zee5",
              bg: Color(red: 0x6B/255, green: 0x18/255, blue: 0xFF/255),
              glow: Color(red: 0xFF/255, green: 0x18/255, blue: 0xA1/255),
              display: .text("ZEE5", Color.white, fontWeight: .black, design: .default)),

        // MARK: - East Asia (46–50)
        .init(id: "iqiyi", name: "iQIYI",
              bg: Color(red: 0x00/255, green: 0xC4/255, blue: 0x6A/255),
              glow: Color(red: 0x00/255, green: 0xF0/255, blue: 0x82/255),
              display: .text("iQ", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "wetv", name: "WeTV",
              bg: Color(red: 0xFC/255, green: 0x52/255, blue: 0x21/255),
              glow: Color(red: 0xFF/255, green: 0x84/255, blue: 0x21/255),
              display: .text("WeTV", Color.white, fontWeight: .black, design: .rounded)),
        .init(id: "viu", name: "Viu",
              bg: Color(red: 0xFF/255, green: 0xCC/255, blue: 0x00/255),
              glow: Color(red: 0xFF/255, green: 0xCC/255, blue: 0x00/255),
              display: .text("Viu", Color.black, fontWeight: .black, design: .rounded)),
        .init(id: "unext", name: "U-NEXT",
              bg: .black,
              glow: Color(red: 0xFF/255, green: 0xFF/255, blue: 0xFF/255),
              display: .text("U", Color.white, fontWeight: .black, design: .serif)),
        .init(id: "abema", name: "ABEMA",
              bg: .black,
              glow: Color(red: 0x00/255, green: 0xE6/255, blue: 0x66/255),
              display: .text("ABEMA", Color(red: 0x00/255, green: 0xE6/255, blue: 0x66/255),
                             fontWeight: .black, design: .default))
    ]

    /// Lookup by stable id. O(n) but the catalogue is small and the call
    /// sites are pill icons / sheet rendering — not perf-critical.
    static func service(for id: String) -> StreamingService? {
        all.first { $0.id == id }
    }

    /// Returns the selected services in catalogue order, dropping unknown ids.
    /// Used so the pill always shows brands in the same priority as the grid.
    static func ordered(from ids: Set<String>) -> [StreamingService] {
        all.filter { ids.contains($0.id) }
    }
}
