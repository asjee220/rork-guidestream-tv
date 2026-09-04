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

    /// The phone's marks, in full — generated from
    /// ios/GuideStreamTV/Models/StreamingService.swift. Regenerate alongside
    /// StreamingCatalog in TVCompatStubs when the phone's list changes; a
    /// service in one and not the other renders as initials.
    static let all: [TVServiceBrand] = [
        .init(id: "netflix", bg: .black,
              display: .text("N", Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255), weight: .black, design: .serif)),
        .init(id: "prime", bg: Color(red: 0x1A/255, green: 0x20/255, blue: 0x2C/255),
              display: .text("prime\nvideo", Color.white, weight: .bold, design: .default)),
        .init(id: "disney", bg: Color(red: 0x0E/255, green: 0x29/255, blue: 0x3F/255),
              display: .text("Disney+", Color.white, weight: .semibold, design: .serif)),
        .init(id: "hbo", bg: Color(red: 0x00/255, green: 0x1E/255, blue: 0xE0/255),
              display: .text("max", Color.white, weight: .black, design: .default)),
        .init(id: "appletv", bg: .black,
              display: .symbolText("applelogo", "tv+", Color.white)),
        .init(id: "paramount", bg: Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255),
              display: .text("P+", Color.white, weight: .black, design: .default)),
        .init(id: "hulu", bg: Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255),
              display: .text("hulu", Color.black, weight: .black, design: .rounded)),
        .init(id: "peacock", bg: .black,
              display: .text("peacock", Color.white, weight: .bold, design: .default)),
        .init(id: "crunchyroll", bg: Color(red: 0xF4/255, green: 0x7B/255, blue: 0x20/255),
              display: .text("crunchyroll", Color.white, weight: .black, design: .rounded)),
        .init(id: "espn", bg: Color(red: 0x00/255, green: 0x1A/255, blue: 0x70/255),
              display: .text("ESPN+", Color.white, weight: .black, design: .default)),
        .init(id: "discovery", bg: Color(red: 0x00/255, green: 0x4D/255, blue: 0xFA/255),
              display: .text("d+", Color.white, weight: .black, design: .rounded)),
        .init(id: "mgm", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("MGM+", Color(red: 0xC7/255, green: 0xA1/255, blue: 0x5A/255), weight: .black, design: .rounded)),
        .init(id: "starz", bg: Color(red: 0x14/255, green: 0x05/255, blue: 0x20/255),
              display: .star),
        .init(id: "showtime", bg: .black,
              display: .text("SHO", Color(red: 0xD8/255, green: 0x00/255, blue: 0x00/255), weight: .black, design: .default)),
        .init(id: "amc", bg: .black,
              display: .text("amc+", Color.white, weight: .black, design: .default)),
        .init(id: "mubi", bg: .black,
              display: .text("MUBI", Color.white, weight: .black, design: .default)),
        .init(id: "dazn", bg: .black,
              display: .text("DAZN", Color(red: 0xF4/255, green: 0x00/255, blue: 0x29/255), weight: .black, design: .default)),
        .init(id: "youtubetv", bg: .white,
              display: .text("YT TV", Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255), weight: .black, design: .rounded)),
        .init(id: "hotstar", bg: Color(red: 0x0A/255, green: 0x11/255, blue: 0x2E/255),
              display: .text("hotstar", Color.white, weight: .black, design: .rounded)),
        .init(id: "zee5", bg: Color(red: 0x6B/255, green: 0x18/255, blue: 0xFF/255),
              display: .text("ZEE5", Color.white, weight: .black, design: .default)),
        .init(id: "sonyliv", bg: .black,
              display: .text("LIV", Color(red: 0xFF/255, green: 0x66/255, blue: 0x00/255), weight: .black, design: .default)),
        .init(id: "sky", bg: Color(red: 0x00/255, green: 0x20/255, blue: 0x4E/255),
              display: .text("sky", Color.white, weight: .black, design: .rounded)),
        .init(id: "nowtv", bg: Color(red: 0x00/255, green: 0x55/255, blue: 0xA4/255),
              display: .text("NOW", Color.white, weight: .black, design: .rounded)),
        .init(id: "skyshowtime", bg: .black,
              display: .text("S+", Color(red: 0xFF/255, green: 0x00/255, blue: 0x73/255), weight: .black, design: .default)),
        .init(id: "canalplus", bg: .black,
              display: .text("CANAL+", Color.white, weight: .black, design: .default)),
        .init(id: "movistar", bg: Color(red: 0x00/255, green: 0x18/255, blue: 0x6B/255),
              display: .text("M+", Color(red: 0x5F/255, green: 0xD0/255, blue: 0xE8/255), weight: .black, design: .rounded)),
        .init(id: "stan", bg: .black,
              display: .text("stan.", Color(red: 0x00/255, green: 0xD4/255, blue: 0xFF/255), weight: .black, design: .rounded)),
        .init(id: "binge", bg: Color(red: 0xFF/255, green: 0x29/255, blue: 0x00/255),
              display: .text("binge", Color.white, weight: .black, design: .rounded)),
        .init(id: "foxtel", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("foxtel", Color.white, weight: .black, design: .rounded)),
        .init(id: "kayo", bg: .black,
              display: .text("Kayo", Color(red: 0x18/255, green: 0xE0/255, blue: 0xC8/255), weight: .black, design: .rounded)),
        .init(id: "globoplay", bg: .black,
              display: .text("globo\nplay", Color.white, weight: .black, design: .rounded)),
        .init(id: "vix", bg: Color(red: 0xFF/255, green: 0x29/255, blue: 0x00/255),
              display: .text("ViX", Color.white, weight: .black, design: .rounded)),
        .init(id: "claro", bg: Color(red: 0xD8/255, green: 0x00/255, blue: 0x0C/255),
              display: .text("claro", Color.white, weight: .black, design: .rounded)),
        .init(id: "crave", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("crave", Color(red: 0x00/255, green: 0xC2/255, blue: 0xA8/255), weight: .black, design: .rounded)),
        .init(id: "tving", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("TVING", Color(red: 0xFF/255, green: 0x15/255, blue: 0x60/255), weight: .black, design: .rounded)),
        .init(id: "wavve", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x12/255),
              display: .text("wavve", Color(red: 0x6E/255, green: 0x86/255, blue: 0xFF/255), weight: .black, design: .rounded)),
        .init(id: "watcha", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("watcha", Color(red: 0xFF/255, green: 0x05/255, blue: 0x58/255), weight: .black, design: .rounded)),
        .init(id: "unext", bg: .black,
              display: .text("U", Color.white, weight: .black, design: .serif)),
        .init(id: "wow", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("WOW", Color(red: 0x00/255, green: 0xE0/255, blue: 0xC8/255), weight: .black, design: .rounded)),
        .init(id: "rtlplus", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("RTL+", Color(red: 0xE4/255, green: 0x00/255, blue: 0x3A/255), weight: .black, design: .rounded)),
        .init(id: "joyn", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("Joyn", Color(red: 0x00/255, green: 0xE0/255, blue: 0xB0/255), weight: .black, design: .rounded)),
        .init(id: "videoland", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("VL", Color(red: 0xFF/255, green: 0x4B/255, blue: 0x00/255), weight: .black, design: .rounded)),
        .init(id: "tf1plus", bg: Color(red: 0x0A/255, green: 0x10/255, blue: 0x30/255),
              display: .text("TF1+", Color(red: 0x6E/255, green: 0x9B/255, blue: 0xFF/255), weight: .black, design: .rounded)),
        .init(id: "m6plus", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("M6+", Color(red: 0xE4/255, green: 0x00/255, blue: 0x7A/255), weight: .black, design: .rounded)),
        .init(id: "viaplay", bg: Color(red: 0x1C/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("via\nplay", Color(red: 0xDB/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "magentatv", bg: Color(red: 0x16/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("Mag\nenta", Color(red: 0x96/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "timvision", bg: Color(red: 0x1E/255, green: 0x17/255, blue: 0x0F/255),
              display: .text("TIM", Color(red: 0xEC/255, green: 0x9E/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "atresplayer", bg: Color(red: 0x0F/255, green: 0x18/255, blue: 0x1E/255),
              display: .text("Atres", Color(red: 0x45/255, green: 0xA9/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "sfrplay", bg: Color(red: 0x12/255, green: 0x0F/255, blue: 0x1E/255),
              display: .text("SFR", Color(red: 0x69/255, green: 0x45/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "nlziet", bg: Color(red: 0x1E/255, green: 0x14/255, blue: 0x0F/255),
              display: .text("NLZIET", Color(red: 0xEC/255, green: 0x7D/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "citytv", bg: Color(red: 0x17/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("City+", Color(red: 0xA4/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "clarotv", bg: Color(red: 0x0F/255, green: 0x17/255, blue: 0x1E/255),
              display: .text("Claro+", Color(red: 0x45/255, green: 0xA4/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "tvaplus", bg: Color(red: 0x0F/255, green: 0x1C/255, blue: 0x1E/255),
              display: .text("TVA+", Color(red: 0x45/255, green: 0xD6/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "noovo", bg: Color(red: 0x0F/255, green: 0x19/255, blue: 0x1E/255),
              display: .text("Noovo", Color(red: 0x45/255, green: 0xB7/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "clubillico", bg: Color(red: 0x1E/255, green: 0x11/255, blue: 0x0F/255),
              display: .text("illico", Color(red: 0xEC/255, green: 0x56/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "rds", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x11/255),
              display: .text("RDS", Color(red: 0xEC/255, green: 0x45/255, blue: 0x58/255), weight: .black, design: .rounded)),
        .init(id: "skygo", bg: Color(red: 0x13/255, green: 0x0F/255, blue: 0x1E/255),
              display: .text("Sky\nGo", Color(red: 0x6F/255, green: 0x45/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "virgintv", bg: Color(red: 0x0F/255, green: 0x12/255, blue: 0x1E/255),
              display: .text("Virgin", Color(red: 0x45/255, green: 0x69/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "allente", bg: Color(red: 0x14/255, green: 0x0F/255, blue: 0x1E/255),
              display: .text("Allente", Color(red: 0x7A/255, green: 0x45/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "strim", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x1A/255),
              display: .text("Strim", Color(red: 0xEC/255, green: 0x45/255, blue: 0xBD/255), weight: .black, design: .rounded)),
        .init(id: "ruutu", bg: Color(red: 0x14/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("Ruutu", Color(red: 0x7F/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "tele2", bg: Color(red: 0x0F/255, green: 0x1E/255, blue: 0x12/255),
              display: .text("Tele2", Color(red: 0x45/255, green: 0xEC/255, blue: 0x66/255), weight: .black, design: .rounded)),
        .init(id: "tv4play", bg: Color(red: 0x16/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("TV4", Color(red: 0x99/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "tv2", bg: Color(red: 0x12/255, green: 0x0F/255, blue: 0x1E/255),
              display: .text("TV2", Color(red: 0x66/255, green: 0x45/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "bet", bg: Color(red: 0x10/255, green: 0x10/255, blue: 0x14/255),
              display: .text("BET+", Color(red: 0xB1/255, green: 0x4E/255, blue: 0xFF/255), weight: .black, design: .rounded)),
        .init(id: "philo", bg: Color(red: 0x0E/255, green: 0x0E/255, blue: 0x12/255),
              display: .text("philo", Color(red: 0x9B/255, green: 0x6B/255, blue: 0xFF/255), weight: .black, design: .rounded)),
        .init(id: "fubo", bg: Color(red: 0xEC/255, green: 0x18/255, blue: 0x40/255),
              display: .text("fubo", Color.white, weight: .black, design: .rounded)),
        .init(id: "sling", bg: .black,
              display: .text("sling", Color(red: 0xFF/255, green: 0x73/255, blue: 0x00/255), weight: .black, design: .rounded)),
        .init(id: "directv", bg: Color(red: 0x00/255, green: 0x20/255, blue: 0x4E/255),
              display: .text("DIRECTV", Color.white, weight: .black, design: .rounded)),
        .init(id: "fox", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("FOX\none", Color(red: 0x00/255, green: 0x89/255, blue: 0xCF/255), weight: .black, design: .rounded)),
        .init(id: "hayu", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("hayu", Color(red: 0x00/255, green: 0xD2/255, blue: 0xA0/255), weight: .black, design: .rounded)),
        .init(id: "britbox", bg: Color(red: 0x12/255, green: 0x33/255, blue: 0x9C/255),
              display: .text("Brit\nBox", Color.white, weight: .black, design: .rounded)),
        .init(id: "britboxuk", bg: Color(red: 0x0F/255, green: 0x12/255, blue: 0x1E/255),
              display: .text("Brit\nUK", Color(red: 0x45/255, green: 0x61/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "acorntv", bg: Color(red: 0x21/255, green: 0x47/255, blue: 0x2A/255),
              display: .text("Acorn", Color.white, weight: .black, design: .serif)),
        .init(id: "hallmark", bg: Color(red: 0x3E/255, green: 0x2A/255, blue: 0x6E/255),
              display: .text("Hall\nmark+", Color.white, weight: .black, design: .rounded)),
        .init(id: "criterion", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("C", Color(red: 0xE8/255, green: 0xE8/255, blue: 0xE8/255), weight: .black, design: .rounded)),
        .init(id: "shudder", bg: .black,
              display: .text("shudder", Color(red: 0x9A/255, green: 0x00/255, blue: 0xFF/255), weight: .black, design: .rounded)),
        .init(id: "hidive", bg: Color(red: 0x0A/255, green: 0x1A/255, blue: 0x2F/255),
              display: .text("HIDIVE", Color(red: 0x00/255, green: 0xC2/255, blue: 0xFF/255), weight: .black, design: .rounded)),
        .init(id: "kanopy", bg: Color(red: 0x11/255, green: 0x11/255, blue: 0x11/255),
              display: .text("kanopy", Color(red: 0xFF/255, green: 0x3B/255, blue: 0x4E/255), weight: .black, design: .rounded)),
        .init(id: "hoopla", bg: Color(red: 0x0A/255, green: 0x2A/255, blue: 0x4A/255),
              display: .text("hoopla", Color(red: 0x00/255, green: 0xA6/255, blue: 0xCE/255), weight: .black, design: .rounded)),
        .init(id: "rakutenviki", bg: Color(red: 0x16/255, green: 0x18/255, blue: 0x29/255),
              display: .text("VIKI", Color(red: 0xBC/255, green: 0x00/255, blue: 0x6C/255), weight: .black, design: .default)),
        .init(id: "bfiplayer", bg: Color(red: 0x1C/255, green: 0x0F/255, blue: 0x1E/255),
              display: .text("BFI", Color(red: 0xD6/255, green: 0x45/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "mlb", bg: Color(red: 0x04/255, green: 0x1E/255, blue: 0x42/255),
              display: .text("MLB", Color.white, weight: .black, design: .rounded)),
        .init(id: "wnba", bg: Color(red: 0xC2/255, green: 0x42/255, blue: 0x00/255),
              display: .text("WNBA", Color.white, weight: .black, design: .rounded)),
        .init(id: "tennis", bg: Color(red: 0x12/255, green: 0x3B/255, blue: 0x2E/255),
              display: .text("TC", Color(red: 0xC6/255, green: 0xFF/255, blue: 0x00/255), weight: .black, design: .rounded)),
        .init(id: "bein", bg: Color(red: 0x0A/255, green: 0x1B/255, blue: 0x2A/255),
              display: .text("beIN", Color(red: 0x9B/255, green: 0x6B/255, blue: 0xFF/255), weight: .black, design: .rounded)),
        .init(id: "f1tv", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("F1", Color(red: 0xE1/255, green: 0x06/255, blue: 0x00/255), weight: .black, design: .rounded)),
        .init(id: "optus", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("Optus", Color(red: 0x7E/255, green: 0xE0/255, blue: 0x00/255), weight: .black, design: .rounded)),
        .init(id: "premier", bg: Color(red: 0x0A/255, green: 0x10/255, blue: 0x30/255),
              display: .text("PS", Color(red: 0xFF/255, green: 0xC0/255, blue: 0x00/255), weight: .black, design: .rounded)),
        .init(id: "skysports", bg: Color(red: 0x00/255, green: 0x1B/255, blue: 0x4E/255),
              display: .text("Sky\nSports", Color.white, weight: .black, design: .rounded)),
        .init(id: "tsn", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("TSN", Color(red: 0xE4/255, green: 0x00/255, blue: 0x2B/255), weight: .black, design: .rounded)),
        .init(id: "sportsnet", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("SN+", Color(red: 0x4A/255, green: 0x9B/255, blue: 0xFF/255), weight: .black, design: .rounded)),
        .init(id: "nwsl", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x15/255),
              display: .text("NWSL", Color(red: 0xEC/255, green: 0x45/255, blue: 0x85/255), weight: .black, design: .rounded)),
        .init(id: "florugby", bg: Color(red: 0x16/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("Flo", Color(red: 0x93/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "kleague", bg: Color(red: 0x0F/255, green: 0x15/255, blue: 0x1E/255),
              display: .text("K\nLeague", Color(red: 0x45/255, green: 0x8D/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "curiosity", bg: Color(red: 0x0A/255, green: 0x12/255, blue: 0x2A/255),
              display: .text("CS", Color(red: 0x00/255, green: 0xC2/255, blue: 0xFF/255), weight: .black, design: .default)),
        .init(id: "tubi", bg: Color(red: 0xD3/255, green: 0x14/255, blue: 0x21/255),
              display: .text("tubi", Color.white, weight: .black, design: .rounded)),
        .init(id: "pluto", bg: Color(red: 0x18/255, green: 0x10/255, blue: 0x37/255),
              display: .text("Pluto", Color(red: 0xFF/255, green: 0xE0/255, blue: 0x36/255), weight: .black, design: .rounded)),
        .init(id: "roku", bg: Color(red: 0x66/255, green: 0x2D/255, blue: 0x91/255),
              display: .text("Roku", Color.white, weight: .black, design: .rounded)),
        .init(id: "plex", bg: .black,
              display: .symbol("play.tv.fill", Color(red: 0xE5/255, green: 0xA0/255, blue: 0x17/255))),
        .init(id: "xumo", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("xumo", Color(red: 0xB4/255, green: 0x7B/255, blue: 0xFF/255), weight: .black, design: .rounded)),
        .init(id: "samsungtvplus", bg: Color(red: 0x0A/255, green: 0x0F/255, blue: 0x2A/255),
              display: .text("Samsung\nTV+", Color(red: 0x4A/255, green: 0x6C/255, blue: 0xF7/255), weight: .black, design: .default)),
        .init(id: "freevee", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("free\nvee", Color(red: 0x00/255, green: 0xA8/255, blue: 0xE1/255), weight: .black, design: .rounded)),
        .init(id: "crackle", bg: .black,
              display: .text("crackle", Color(red: 0xFF/255, green: 0xA8/255, blue: 0x00/255), weight: .black, design: .rounded)),
        .init(id: "popcornflix", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("PF", Color(red: 0xFF/255, green: 0x2E/255, blue: 0x00/255), weight: .black, design: .rounded)),
        .init(id: "cineverse", bg: Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
              display: .text("CV", Color(red: 0x00/255, green: 0xD0/255, blue: 0xC0/255), weight: .black, design: .rounded)),
        .init(id: "ondemandkorea", bg: Color(red: 0x0A/255, green: 0x0E/255, blue: 0x27/255),
              display: .text("ODK", Color(red: 0x6E/255, green: 0x9B/255, blue: 0xFF/255), weight: .black, design: .rounded)),
        .init(id: "mercado", bg: Color(red: 0x0A/255, green: 0x1A/255, blue: 0x0A/255),
              display: .text("MP", Color(red: 0xFF/255, green: 0xE6/255, blue: 0x00/255), weight: .black, design: .rounded)),
        .init(id: "fawesome", bg: Color(red: 0x12/255, green: 0x0F/255, blue: 0x1E/255),
              display: .text("Fawe\nsome", Color(red: 0x69/255, green: 0x45/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "youtube", bg: .black,
              display: .symbol("play.rectangle.fill", Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255))),
        .init(id: "bbciplayer", bg: .black,
              display: .text("iPlayer", Color(red: 0xFB/255, green: 0xB0/255, blue: 0x32/255), weight: .black, design: .default)),
        .init(id: "itvx", bg: .black,
              display: .text("ITVX", Color.white, weight: .black, design: .rounded)),
        .init(id: "channel4", bg: .black,
              display: .text("4", Color(red: 0xAA/255, green: 0xFF/255, blue: 0x00/255), weight: .black, design: .rounded)),
        .init(id: "my5", bg: Color(red: 0x1E/255, green: 0x19/255, blue: 0x0F/255),
              display: .text("My5", Color(red: 0xEC/255, green: 0xB7/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "uktv", bg: Color(red: 0x0F/255, green: 0x12/255, blue: 0x1E/255),
              display: .text("UKTV", Color(red: 0x45/255, green: 0x66/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "7plus", bg: Color(red: 0x0F/255, green: 0x1E/255, blue: 0x1D/255),
              display: .text("7+", Color(red: 0x45/255, green: 0xEC/255, blue: 0xE4/255), weight: .black, design: .rounded)),
        .init(id: "9now", bg: Color(red: 0x1E/255, green: 0x10/255, blue: 0x0F/255),
              display: .text("9Now", Color(red: 0xEC/255, green: 0x53/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "tenplay", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x13/255),
              display: .text("10", Color(red: 0xEC/255, green: 0x45/255, blue: 0x6F/255), weight: .black, design: .rounded)),
        .init(id: "iview", bg: Color(red: 0x17/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("iview", Color(red: 0x9E/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "sbs", bg: Color(red: 0x0F/255, green: 0x19/255, blue: 0x1E/255),
              display: .text("SBS", Color(red: 0x45/255, green: 0xB4/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "tvnz", bg: Color(red: 0x1E/255, green: 0x14/255, blue: 0x0F/255),
              display: .text("TVNZ+", Color(red: 0xEC/255, green: 0x7F/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "ctv", bg: Color(red: 0x10/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("CTV", Color(red: 0x4D/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "cbcgem", bg: Color(red: 0x1E/255, green: 0x10/255, blue: 0x0F/255),
              display: .text("Gem", Color(red: 0xEC/255, green: 0x4D/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "globaltv", bg: Color(red: 0x1E/255, green: 0x13/255, blue: 0x0F/255),
              display: .text("Global", Color(red: 0xEC/255, green: 0x6F/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "zdf", bg: Color(red: 0x12/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("ZDF", Color(red: 0x66/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "ardplus", bg: Color(red: 0x1E/255, green: 0x11/255, blue: 0x0F/255),
              display: .text("ARD", Color(red: 0xEC/255, green: 0x58/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "toggo", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x16/255),
              display: .text("Toggo", Color(red: 0xEC/255, green: 0x45/255, blue: 0x93/255), weight: .black, design: .rounded)),
        .init(id: "ae", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x11/255),
              display: .text("A&E", Color(red: 0xEC/255, green: 0x45/255, blue: 0x5B/255), weight: .black, design: .rounded)),
        .init(id: "hgtv", bg: Color(red: 0x1B/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("HGTV", Color(red: 0xC8/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "usa", bg: Color(red: 0x18/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("USA", Color(red: 0xAC/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "syfy", bg: Color(red: 0x0F/255, green: 0x15/255, blue: 0x1E/255),
              display: .text("syfy", Color(red: 0x45/255, green: 0x85/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "mtv", bg: Color(red: 0x1E/255, green: 0x11/255, blue: 0x0F/255),
              display: .text("MTV", Color(red: 0xEC/255, green: 0x58/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "vh1", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x17/255),
              display: .text("VH1", Color(red: 0xEC/255, green: 0x45/255, blue: 0xA1/255), weight: .black, design: .rounded)),
        .init(id: "tvland", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x13/255),
              display: .text("TV\nLand", Color(red: 0xEC/255, green: 0x45/255, blue: 0x6F/255), weight: .black, design: .rounded)),
        .init(id: "lifetime", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x1D/255),
              display: .text("LT", Color(red: 0xEC/255, green: 0x45/255, blue: 0xDE/255), weight: .black, design: .rounded)),
        .init(id: "foodnetwork", bg: Color(red: 0x0F/255, green: 0x1E/255, blue: 0x1E/255),
              display: .text("Food", Color(red: 0x45/255, green: 0xEC/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "travel", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x1E/255),
              display: .text("Travel", Color(red: 0xEC/255, green: 0x45/255, blue: 0xE9/255), weight: .black, design: .rounded)),
        .init(id: "national", bg: Color(red: 0x0F/255, green: 0x14/255, blue: 0x1E/255),
              display: .text("Nat\nGeo", Color(red: 0x45/255, green: 0x7A/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "investigation", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x11/255),
              display: .text("ID", Color(red: 0xEC/255, green: 0x45/255, blue: 0x56/255), weight: .black, design: .rounded)),
        .init(id: "history", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x1D/255),
              display: .text("HIST", Color(red: 0xEC/255, green: 0x45/255, blue: 0xE1/255), weight: .black, design: .rounded)),
        .init(id: "cartoon", bg: Color(red: 0x1E/255, green: 0x10/255, blue: 0x0F/255),
              display: .text("CN", Color(red: 0xEC/255, green: 0x50/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "adultswim", bg: Color(red: 0x1E/255, green: 0x1C/255, blue: 0x0F/255),
              display: .text("[as]", Color(red: 0xEC/255, green: 0xDB/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "freeform", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x1B/255),
              display: .text("FF", Color(red: 0xEC/255, green: 0x45/255, blue: 0xCB/255), weight: .black, design: .rounded)),
        .init(id: "cw", bg: Color(red: 0x0F/255, green: 0x10/255, blue: 0x1E/255),
              display: .text("CW", Color(red: 0x45/255, green: 0x53/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "cbs", bg: Color(red: 0x18/255, green: 0x0F/255, blue: 0x1E/255),
              display: .text("CBS", Color(red: 0xA9/255, green: 0x45/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "nbc", bg: Color(red: 0x1E/255, green: 0x17/255, blue: 0x0F/255),
              display: .text("NBC", Color(red: 0xEC/255, green: 0x9B/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "foxnet", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x17/255),
              display: .text("FOX", Color(red: 0xEC/255, green: 0x45/255, blue: 0xA1/255), weight: .black, design: .rounded)),
        .init(id: "pbs", bg: Color(red: 0x0F/255, green: 0x1E/255, blue: 0x1B/255),
              display: .text("PBS", Color(red: 0x45/255, green: 0xEC/255, blue: 0xCD/255), weight: .black, design: .rounded)),
        .init(id: "pbskids", bg: Color(red: 0x10/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("PBS\nKids", Color(red: 0x50/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "bbcamerica", bg: Color(red: 0x19/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("BBC\nUSA", Color(red: 0xB2/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "wowpresents", bg: Color(red: 0x0F/255, green: 0x17/255, blue: 0x1E/255),
              display: .text("WOW+", Color(red: 0x45/255, green: 0x9B/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "kocowa", bg: Color(red: 0x1E/255, green: 0x19/255, blue: 0x0F/255),
              display: .text("KOCOWA", Color(red: 0xEC/255, green: 0xBA/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "sunnxt", bg: Color(red: 0x17/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("Sun\nNxt", Color(red: 0xA4/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "hungama", bg: Color(red: 0x0F/255, green: 0x16/255, blue: 0x1E/255),
              display: .text("Hun\ngama", Color(red: 0x45/255, green: 0x90/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "arrow", bg: Color(red: 0x1E/255, green: 0x1B/255, blue: 0x0F/255),
              display: .text("ARROW", Color(red: 0xEC/255, green: 0xC8/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "fandor", bg: Color(red: 0x0F/255, green: 0x16/255, blue: 0x1E/255),
              display: .text("fandor", Color(red: 0x45/255, green: 0x93/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "mhz", bg: Color(red: 0x0F/255, green: 0x1E/255, blue: 0x1B/255),
              display: .text("MHz", Color(red: 0x45/255, green: 0xEC/255, blue: 0xD0/255), weight: .black, design: .rounded)),
        .init(id: "topic", bg: Color(red: 0x1E/255, green: 0x17/255, blue: 0x0F/255),
              display: .text("Topic", Color(red: 0xEC/255, green: 0x9B/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "sundance", bg: Color(red: 0x17/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("Sun\ndance", Color(red: 0xA1/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "darkmatter", bg: Color(red: 0x12/255, green: 0x0F/255, blue: 0x1E/255),
              display: .text("DM", Color(red: 0x64/255, green: 0x45/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "flixpremiere", bg: Color(red: 0x0F/255, green: 0x1E/255, blue: 0x1E/255),
              display: .text("FP", Color(red: 0x45/255, green: 0xEC/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "flixfling", bg: Color(red: 0x0F/255, green: 0x0F/255, blue: 0x1E/255),
              display: .text("FxF", Color(red: 0x45/255, green: 0x48/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "animation", bg: Color(red: 0x1E/255, green: 0x12/255, blue: 0x0F/255),
              display: .text("ADN", Color(red: 0xEC/255, green: 0x61/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "wwe", bg: Color(red: 0x16/255, green: 0x1E/255, blue: 0x0F/255),
              display: .text("WWE", Color(red: 0x96/255, green: 0xEC/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "hollywoodsuite", bg: Color(red: 0x13/255, green: 0x0F/255, blue: 0x1E/255),
              display: .text("HS", Color(red: 0x6F/255, green: 0x45/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "guidedoc", bg: Color(red: 0x0F/255, green: 0x1E/255, blue: 0x1C/255),
              display: .text("Guide\nDoc", Color(red: 0x45/255, green: 0xEC/255, blue: 0xD6/255), weight: .black, design: .rounded)),
        .init(id: "beamafilm", bg: Color(red: 0x1E/255, green: 0x1C/255, blue: 0x0F/255),
              display: .text("BF", Color(red: 0xEC/255, green: 0xDB/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "filmin", bg: Color(red: 0x1E/255, green: 0x1D/255, blue: 0x0F/255),
              display: .text("FILMIN", Color(red: 0xEC/255, green: 0xE4/255, blue: 0x45/255), weight: .black, design: .rounded)),
        .init(id: "neon", bg: Color(red: 0x0F/255, green: 0x16/255, blue: 0x1E/255),
              display: .text("NEON", Color(red: 0x45/255, green: 0x93/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "shoutfactory", bg: Color(red: 0x1D/255, green: 0x0F/255, blue: 0x1E/255),
              display: .text("Shout!", Color(red: 0xE1/255, green: 0x45/255, blue: 0xEC/255), weight: .black, design: .rounded)),
        .init(id: "fod", bg: Color(red: 0x1E/255, green: 0x0F/255, blue: 0x1C/255),
              display: .text("FOD", Color(red: 0xEC/255, green: 0x45/255, blue: 0xD9/255), weight: .black, design: .rounded)),
        .init(id: "jiocinema", bg: Color(red: 0xE4/255, green: 0x1F/255, blue: 0x1F/255),
              display: .text("Jio", Color.white, weight: .black, design: .rounded)),
        .init(id: "raiplay", bg: Color(red: 0x00/255, green: 0x47/255, blue: 0xC8/255),
              display: .text("Rai\nPlay", Color.white, weight: .black, design: .rounded)),
        .init(id: "iqiyi", bg: Color(red: 0x00/255, green: 0xC4/255, blue: 0x6A/255),
              display: .text("iQ", Color.white, weight: .black, design: .rounded)),
        .init(id: "wetv", bg: Color(red: 0xFC/255, green: 0x52/255, blue: 0x21/255),
              display: .text("WeTV", Color.white, weight: .black, design: .rounded)),
        .init(id: "viu", bg: Color(red: 0xFF/255, green: 0xCC/255, blue: 0x00/255),
              display: .text("Viu", Color.black, weight: .black, design: .rounded)),
        .init(id: "abema", bg: .black,
              display: .text("ABEMA", Color(red: 0x00/255, green: 0xE6/255, blue: 0x66/255), weight: .black, design: .default)),

        // Aliases kept from the tvOS-only list so a lookup by provider
        // name still resolves these. Not offered as pickable services —
        // StreamingCatalog carries the phone's ids, which are canonical
        // because selected services sync from the account.
        .init(id: "amazonvideo", bg: rgb(0x1A, 0x20, 0x2C), display: .text("prime\nvideo", .white, weight: .bold, design: .default)),
        .init(id: "appletvstore", bg: .black, display: .symbolText("applelogo", "tv", .white)),
        .init(id: "fandango", bg: rgb(0xFF, 0x62, 0x00), display: .text("fandango", .white, weight: .black, design: .rounded)),
        .init(id: "max", bg: rgb(0x00, 0x1E, 0xE0), display: .text("max", .white, weight: .black, design: .default)),
        .init(id: "vudu", bg: rgb(0x00, 0x9E, 0xE0), display: .text("vudu", .white, weight: .black, design: .rounded)),
        .init(id: "googleplay", bg: .white, display: .symbol("play.fill", rgb(0x1A, 0x73, 0xE8)))
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
