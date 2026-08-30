//
//  MediaTypeGlyph.swift
//  GuideStreamTV / GuideStreamTVTV
//
//  The movie / series glyph that sits beside a title in the home rails
//  (GUI-70). A member of the Shared group, so iOS and tvOS draw the identical
//  shape from one definition.
//
//  Hand-drawn rather than SF Symbols on purpose: SF Symbols has no television
//  with an antenna — `tv` is a flat panel on a stand — and Android's Material
//  set draws both shapes differently again. Three platforms could not have
//  looked the same any other way. The Compose twin lives in
//  android/.../ui/components/MediaTypeGlyph.kt and traces the same 24-unit
//  grid; change one, change the other.
//

import SwiftUI

/// Which glyph to draw. Deliberately not `Bool` at the call site — `isTV` reads
/// as a data flag, this reads as a picture.
enum MediaTypeGlyphKind {
    case movie
    case series

    init(isTV: Bool) {
        self = isTV ? .series : .movie
    }
}

/// A film strip (movie) or an antenna television (series), stroked on a
/// 24×24 grid and scaled to `size`. Sized in points so it tracks Dynamic Type
/// when the caller scales it.
struct MediaTypeGlyph: View {
    let kind: MediaTypeGlyphKind
    var size: CGFloat = 12
    var color: Color = Color.white.opacity(0.62)

    /// Stroke weight at 24pt, scaled with the glyph so the shape keeps its
    /// proportions instead of going spindly at small sizes.
    private var lineWidth: CGFloat { 1.7 * (size / 24) }

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) / 24
            let stroke = StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
            context.stroke(
                path(scale: s),
                with: .color(color),
                style: stroke
            )
        }
        .frame(width: size, height: size)
        // The glyph repeats the media type already announced by the title's
        // own accessibility context; announcing it twice is noise.
        .accessibilityHidden(true)
    }

    private func path(scale s: CGFloat) -> Path {
        var p = Path()
        switch kind {
        case .movie:
            // Film strip: a body with a sprocket column down each side.
            p.addRoundedRect(
                in: CGRect(x: 2.5 * s, y: 4.5 * s, width: 19 * s, height: 15 * s),
                cornerSize: CGSize(width: 2.5 * s, height: 2.5 * s)
            )
            for x in [7.0, 17.0] {
                p.move(to: CGPoint(x: x * s, y: 4.5 * s))
                p.addLine(to: CGPoint(x: x * s, y: 19.5 * s))
            }
            for y in [9.5, 14.5] {
                p.move(to: CGPoint(x: 2.5 * s, y: y * s))
                p.addLine(to: CGPoint(x: 7 * s, y: y * s))
                p.move(to: CGPoint(x: 17 * s, y: y * s))
                p.addLine(to: CGPoint(x: 21.5 * s, y: y * s))
            }
        case .series:
            // Television with rabbit-ear antennae.
            p.addRoundedRect(
                in: CGRect(x: 2.5 * s, y: 9 * s, width: 19 * s, height: 12 * s),
                cornerSize: CGSize(width: 2.5 * s, height: 2.5 * s)
            )
            p.move(to: CGPoint(x: 8 * s, y: 9 * s))
            p.addLine(to: CGPoint(x: 5 * s, y: 3.5 * s))
            p.move(to: CGPoint(x: 16 * s, y: 9 * s))
            p.addLine(to: CGPoint(x: 19 * s, y: 3.5 * s))
        }
        return p
    }
}

extension MediaTypeGlyph {
    init(isTV: Bool, size: CGFloat = 12, color: Color = Color.white.opacity(0.62)) {
        self.init(kind: MediaTypeGlyphKind(isTV: isTV), size: size, color: color)
    }
}
