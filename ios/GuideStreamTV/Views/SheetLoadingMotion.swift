//
//  SheetLoadingMotion.swift
//  GuideStreamTV
//
//  Entrance motion for the detail sheet, the full-details screen and the
//  Play-on sheet, so none of them read like a web page waiting on a network
//  call before it draws. Two ideas, both implemented here:
//
//  A — Reserved Frame. Every pending slot is mounted at its FINAL size from
//      the first frame and breathes in place. Nothing below a slot ever moves
//      when its data lands, because the space was always there.
//
//  B — Service Lock-On. While a source lookup runs, the service chip and the
//      platform pill flick through real brand marks, decelerating as the
//      lookup ages. On resolve they snap onto the real service with a spring,
//      a one-frame rim flash and a light haptic. A spinner says "wait"; a
//      shuffle that stops on Paramount+ says "I checked, and this is the one."
//
//  Everything here honours Reduce Motion by collapsing to a static
//  placeholder and an instant swap.
//
//  Spec: claude/detail-sheet-motion-spec-aug2026.md
//

import SwiftUI
import UIKit

// MARK: - Timing

enum SheetMotion {
    /// Breathing period for pending placeholders.
    static let breathePeriod: Double = 1.8
    /// Slower period used once a lookup has been running a while, so a long
    /// wait reads as "still working" rather than "stuck".
    static let patiencePeriod: Double = 2.6
    /// How long a lookup runs before it is treated as slow.
    static let patienceThreshold: Double = 4.0

    /// Shuffle frame duration at the start of a lookup, and the duration it
    /// decelerates toward as the lookup ages.
    static let shuffleFrame: Double = 0.11
    static let shuffleFrameSlow: Double = 0.19

    /// Travel period of the CTA sheen that replaces the spinner.
    static let sheenPeriod: Double = 1.15

    static let lockSpring = Animation.spring(response: 0.32, dampingFraction: 0.55)
    static let settle = Animation.easeOut(duration: 0.22)

    /// Real US services the shuffle cycles through — every one of these has a
    /// brand colour in `gsBrandColor`, so a flick frame never renders grey.
    static let shufflePool: [String] = [
        "Netflix", "Paramount+", "Max", "Hulu",
        "Prime Video", "Peacock", "Disney+", "Apple TV+"
    ]

    /// Placeholder chip name-bar widths. Three chips of uneven width read as
    /// content-shaped rather than as a loading widget.
    static let placeholderWidths: [CGFloat] = [72, 56, 88]

    static func breathe(_ t: Double) -> Double {
        let period = t > patienceThreshold ? patiencePeriod : breathePeriod
        return 0.55 + 0.30 * (0.5 + 0.5 * sin(t * 2 * .pi / period))
    }

    /// Shuffle index for elapsed time `t`, offset by `seed` so sibling chips
    /// never show the same service on the same frame.
    static func shuffleName(_ t: Double, seed: Int) -> String {
        let step = min(shuffleFrameSlow, shuffleFrame + t * 0.02)
        let frame = Int(max(0, t) / step) + seed * 3
        return shufflePool[frame % shufflePool.count]
    }
}

// MARK: - A · Reserved Frame

/// A shape that breathes between 0.55 and 0.85 opacity. Deliberately not a
/// shimmer sweep — a travelling highlight is itself a web idiom, and it reads
/// as decoration rather than as work in progress.
struct BreathingPlaceholder<S: Shape>: View {
    let shape: S
    var fill: Color = Color.white.opacity(0.12)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        if reduceMotion {
            shape.fill(fill.opacity(0.7))
        } else {
            TimelineView(.animation) { ctx in
                shape
                    .fill(fill)
                    .opacity(SheetMotion.breathe(ctx.date.timeIntervalSince(start)))
            }
        }
    }
}

/// Pending stand-in for `ServiceBadge`. Mirrors its paddings, corner radius
/// and outer `.padding(.top/.trailing, 8)` exactly, so the strip does not
/// change height or baseline when real chips replace it.
struct PendingServiceChip: View {
    let nameWidth: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            BreathingPlaceholder(shape: Circle())
                .frame(width: 8, height: 8)
            BreathingPlaceholder(shape: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .frame(width: nameWidth, height: 17)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.top, 8)
        .padding(.trailing, 8)
        .accessibilityHidden(true)
    }
}

/// Full pending "Where to Watch" strip: three uneven chips at the exact
/// height of the loaded row.
struct PendingServiceStrip: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(SheetMotion.placeholderWidths.enumerated()), id: \.offset) { _, w in
                PendingServiceChip(nameWidth: w)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Finding streaming services")
    }
}

/// Pending stand-in for a line of body copy.
struct PendingTextLines: View {
    var widths: [CGFloat] = [1.0, 0.96, 0.78]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                GeometryReader { geo in
                    BreathingPlaceholder(shape: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .frame(width: geo.size.width * w, height: 9)
                }
                .frame(height: 9)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - B · Service Lock-On

/// A `ServiceBadge`-shaped chip that flicks through real brand marks while a
/// lookup runs. Renders at the same size as the loaded chip, so this is also
/// a Reserved Frame slot — B never costs a layout shift to buy.
struct ShufflingServiceChip: View {
    var seed: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        if reduceMotion {
            PendingServiceChip(nameWidth: SheetMotion.placeholderWidths[seed % SheetMotion.placeholderWidths.count])
        } else {
            TimelineView(.animation) { ctx in
                let name = SheetMotion.shuffleName(ctx.date.timeIntervalSince(start), seed: seed)
                ServiceBadge(name: name, color: gsBrandColor(for: name))
                    .opacity(0.72)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Platform pill (header badge, Play-on sheet) that shuffles while resolving.
struct ShufflingPlatformPill: View {
    var seed: Int = 0
    var fontSize: CGFloat = 11

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        if reduceMotion {
            BreathingPlaceholder(shape: Capsule())
                .frame(width: 86, height: 24)
        } else {
            TimelineView(.animation) { ctx in
                let name = SheetMotion.shuffleName(ctx.date.timeIntervalSince(start), seed: seed)
                Text(gsDisplayName(for: name).uppercased())
                    .scaledFont(size: fontSize, weight: .heavy)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(gsBrandColor(for: name)))
                    .opacity(0.9)
            }
            .accessibilityHidden(true)
        }
    }
}

/// Snap-to-resolved treatment: a spring overshoot, a one-frame rim flash and
/// a light haptic when `isResolved` flips true. `delay` staggers siblings so
/// a row of chips locks left to right rather than all at once.
private struct LockOnModifier: ViewModifier {
    let isResolved: Bool
    let delay: Double
    let cornerRadius: CGFloat
    let haptic: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: CGFloat = 1
    @State private var rim: Double = 0
    /// One-shot. The CTA's resolving flag can legitimately flip back to true
    /// while the episode-level deep link resolves; locking twice would read as
    /// a stutter, and would fire the haptic twice for one answer.
    @State private var didFire = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pop)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(rim), lineWidth: 1.5)
                    .allowsHitTesting(false)
            )
            .onChange(of: isResolved) { _, resolved in
                guard resolved, !didFire, !reduceMotion else { return }
                didFire = true
                Task { @MainActor in
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    if haptic { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    withAnimation(SheetMotion.lockSpring) { pop = 1.06 }
                    withAnimation(.easeOut(duration: 0.16)) { rim = 0.45 }
                    try? await Task.sleep(for: .milliseconds(160))
                    withAnimation(SheetMotion.lockSpring) { pop = 1.0 }
                    withAnimation(.easeOut(duration: 0.20)) { rim = 0 }
                }
            }
    }
}

/// Same snap, but fired once when the view first appears. Used for the loaded
/// service chips, which do not exist until the moment they resolve — an
/// `onChange` on them would never fire because they are born already true.
private struct LockOnAppearModifier: ViewModifier {
    let delay: Double
    let cornerRadius: CGFloat
    let haptic: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: CGFloat = 1
    @State private var rim: Double = 0
    @State private var didPop = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pop)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(rim), lineWidth: 1.5)
                    .allowsHitTesting(false)
            )
            .task {
                guard !didPop, !reduceMotion else { return }
                didPop = true
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                if haptic { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                withAnimation(SheetMotion.lockSpring) { pop = 1.06 }
                withAnimation(.easeOut(duration: 0.16)) { rim = 0.45 }
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(SheetMotion.lockSpring) { pop = 1.0 }
                withAnimation(.easeOut(duration: 0.20)) { rim = 0 }
            }
    }
}

extension View {
    /// Lock-on snap for a view whose identity survives the pending → resolved
    /// transition (the platform pill, the Watch CTA).
    func lockOn(isResolved: Bool, delay: Double = 0, cornerRadius: CGFloat = 12,
                haptic: Bool = false) -> some View {
        modifier(LockOnModifier(isResolved: isResolved, delay: delay,
                                cornerRadius: cornerRadius, haptic: haptic))
    }

    /// Lock-on snap for a view that is created at the moment of resolution.
    func lockOnAppear(delay: Double = 0, cornerRadius: CGFloat = 12,
                      haptic: Bool = false) -> some View {
        modifier(LockOnAppearModifier(delay: delay, cornerRadius: cornerRadius, haptic: haptic))
    }
}

// MARK: - CTA sheen

/// Replaces `ProgressView` inside the orange Watch capsule. A highlight band
/// travels the button once every 1.15s: same "something is happening" signal,
/// but it belongs to the button instead of sitting on top of it.
struct CTASheen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            GeometryReader { geo in
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSince(start)
                    let p = t.truncatingRemainder(dividingBy: SheetMotion.sheenPeriod) / SheetMotion.sheenPeriod
                    let band = geo.size.width * 0.44
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.30), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: band)
                    .offset(x: -band + CGFloat(p) * (geo.size.width + band * 2))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// CTA label while a lookup is in flight. Softens to "Still looking…" once the
/// lookup passes the patience threshold, so a slow network gets an honest
/// answer instead of a sentence that stopped being true three seconds ago.
struct ResolvingCTALabel: View {
    var size: CGFloat = 17

    @State private var start = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let slow = ctx.date.timeIntervalSince(start) > SheetMotion.patienceThreshold
            Text(slow ? "Still looking…" : "Finding service…")
                .scaledFont(size: size, weight: .semibold)
                .lineLimit(1)
        }
    }
}
